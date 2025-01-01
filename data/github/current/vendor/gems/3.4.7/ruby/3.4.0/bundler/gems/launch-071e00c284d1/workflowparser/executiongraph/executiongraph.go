package executiongraph

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/github/launch/model"
	"github.com/github/launch/workflowparser"
)

// BuildExecutionGraph returns the parsed ExecutionGraph for a workflow
func BuildExecutionGraph(w *workflowparser.Workflow) (ExecutionGraph, error) {
	if w == nil {
		return ExecutionGraph{}, nil
	}

	var jobs []*Job
	var err error
	keyedJobs := map[string]*Job{}
	jobs, err = getJobs(w, nil, keyedJobs)

	if err != nil {
		return ExecutionGraph{}, err
	}

	// Group jobs by equivalent inputs and outputs
	groups := map[string]*Group{}
	needsMap := map[string]string{}
	for _, job := range jobs {
		key := job.needsNeededKey()
		if _, ok := groups[key]; !ok {
			groupType := GroupTypeDefault
			// order of if else ifs is important
			if job.isWorkflowMatrix {
				groupType = GroupTypeWorkflowMatrix
			} else if job.isMatrix {
				groupType = GroupTypeMatrix
			} else if job.isStrategyExpression {
				groupType = GroupTypeStrategyExpression
			}
			groups[key] = &Group{
				ID:   key,
				Type: groupType,
			}

			if job.isMatrix {
				groups[key].Name = job.nameOrID()
			}
		}

		groups[key].addJob(job)
		needsMap[strings.ToLower(job.ID)] = key
	}

	for _, group := range groups {
		job := group.Jobs[0] // All jobs in this group should have the same dependencies
		for _, input := range job.inputs {
			group.addInput(needsMap[strings.ToLower(input)])
		}
		for _, output := range job.outputs {
			group.addOutput(needsMap[strings.ToLower(output)])
		}
	}

	stages, err := orderedStages(groups)
	if err != nil {
		return ExecutionGraph{}, err
	}

	return ExecutionGraph{
		Stages: stages,
	}, nil
}

func orderedStages(groups map[string]*Group) ([]Stage, error) {
	// Create dependencies map and "seen" map for each group
	dependencies := map[string][]*Group{}
	seen := map[*Group]bool{}
	processed := map[*Group]bool{}

	for _, group := range groups {
		if len(group.Inputs) > 0 {
			for _, need := range group.Inputs {
				if _, ok := dependencies[need]; !ok {
					dependencies[need] = []*Group{}
				}
				dependencies[need] = append(dependencies[need], group)
				processed[group] = false
			}
		} else {
			dependencies[""] = append(dependencies[""], group)
			processed[group] = true
		}

		seen[group] = false
	}

	// Sort dependencies so each array of them is ordered by num outputs DESC, or ID if tied
	for _, v := range dependencies {
		sort.SliceStable(v, func(i, j int) bool {
			if len(v[i].Outputs) == len(v[j].Outputs) {
				return v[i].ID < v[j].ID
			}
			return len(v[i].Outputs) > len(v[j].Outputs)
		})
	}

	// Prime the queue with the groups that have no dependencies
	queue := []*Group{}
	queue = append(queue, dependencies[""]...)
	var endOfStage *Group // Nil group
	queue = append(queue, endOfStage)

	stages := []Stage{}
	currentStage := Stage{Groups: []Group{}}

	for len(queue) > 0 {
		group := queue[0]
		queue = queue[1:]

		if group == endOfStage {
			// Close current stage
			stages = append(stages, currentStage)
			currentStage = Stage{Groups: []Group{}}

			// Add another marker to the end of the queue unless we are done
			if len(queue) > 0 {
				queue = append(queue, nil)
			}

		} else {
			seen[group] = true
			currentStage.Groups = append(currentStage.Groups, *group)

			// Add dependent groups to the end of queue if we have seen all their parent dependencies
			for _, dependentGroup := range dependencies[group.ID] {
				allSeen := true
				for _, need := range dependentGroup.Inputs {
					g := groups[need]
					if !seen[g] {
						allSeen = false
					}
				}
				if allSeen && !processed[dependentGroup] {
					queue = append(queue, dependentGroup)
					processed[dependentGroup] = true
				}
			}
		}
	}

	// Return an error if we didn't process every job
	for _, groupProcessed := range processed {
		if !groupProcessed {
			return stages, errors.New("Some jobs are unreachable")
		}
	}
	return stages, nil
}

// getEnvironmentID returns a grouping ID based on environment name
func getEnvironmentID(j *model.Job) string {
	if j.Environment == nil || j.Environment.IsDynamic {
		return ""
	}
	envID := strings.ToLower(j.Environment.Name)
	return fmt.Sprintf("env:%s", envID)
}

// ToJSON returns the JSON representation of a parsed execution graph
func (graph *ExecutionGraph) ToJSON() (string, error) {
	if graph == nil {
		return "", errors.New("graph must not be nil")
	}
	// This custom encoder avoids turning `&` into `\\u0026`
	buf := new(bytes.Buffer)
	enc := json.NewEncoder(buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(graph); err != nil {
		return "", fmt.Errorf("failed to json-encode graph: %v", err)
	}
	return strings.TrimSpace(buf.String()), nil
}

type callerToJobs struct {
	callerID   string
	calledJobs []*Job
}

// callerJobInfo contains the ID and name of the calling job
type callerJobInfo struct {
	ID   string
	Name string
}

//gocyclo:ignore
func getJobs(w *workflowparser.Workflow, caller *callerJobInfo, keyedJobs map[string]*Job) ([]*Job, error) {
	var jobs []*Job
	var calledJobsMap []callerToJobs

	for _, modelJob := range w.Jobs() {
		for _, need := range modelJob.Needs {
			if modelJob.ID == need {
				return nil, errors.New("self-referential job.needs")
			}
		}

		originalJobID := modelJob.ID
		resolvedJobID := modelJob.ID
		resolvedJobName := modelJob.Name
		var jobNeeds []string
		jobNeeds = append(jobNeeds, modelJob.Needs...)
		// Namespacing to avoid duplicate job ids and names
		if caller != nil {
			callerJobID := caller.ID
			if callerJobID != "" {
				resolvedJobID = callerJobID + "." + modelJob.ID
				for i, need := range modelJob.Needs {
					jobNeeds[i] = callerJobID + "." + need
				}
			}
			callerName := caller.Name
			if callerName == "" {
				callerName = strings.Replace(callerJobID, ".", " / ", -1) //nolint:gocritic
			}
			jobNameString := originalJobID
			if modelJob.Name != nil {
				jobNameString = *modelJob.Name
			}
			jobNameString = callerName + " / " + jobNameString
			resolvedJobName = &jobNameString
		}

		// If job calls another workflow, get those jobs and add to keyedJobs so they can be referenced
		// If job uses a matrix, skip called workflow since it will all be flattened under the caller matrix job
		calledWorkflow, ok := w.CalledWorkflows[originalJobID]
		if ok && !modelJob.IsMatrix() && !modelJob.IsStrategyExpression() {
			newCaller := callerJobInfo{
				ID: resolvedJobID,
			}
			if modelJob.Name != nil {
				newCaller.Name = *resolvedJobName
			}
			calledJobs, err := getJobs(&calledWorkflow.Workflow, &newCaller, keyedJobs)
			if err != nil {
				return nil, err
			}
			calledJobsMap = append(calledJobsMap, callerToJobs{
				callerID:   strings.ToLower(resolvedJobID),
				calledJobs: calledJobs,
			})
		}

		isWorkflowMatrix := ok && (modelJob.IsMatrix() || modelJob.IsStrategyExpression())

		job := Job{
			ID:                   resolvedJobID,
			Name:                 resolvedJobName,
			isMatrix:             modelJob.IsMatrix(),
			isStrategyExpression: modelJob.IsStrategyExpression(),
			isWorkflowMatrix:     isWorkflowMatrix,
			environmentID:        getEnvironmentID(modelJob),
			inputs:               jobNeeds,
		}
		jobs = append(jobs, &job)
		keyedJobs[strings.ToLower(job.ID)] = &job
	}

	// Set all the job outputs
	for _, job := range jobs {
		for _, input := range job.inputs {
			inputKey := strings.ToLower(input)
			if _, ok := keyedJobs[inputKey]; !ok {
				return nil, errors.New("job.needs points to non-existent job key")
			}
			keyedJobs[inputKey].addOutput(strings.ToLower(job.ID))
		}
	}

	for _, callerToJobs := range calledJobsMap {
		callerJobID := callerToJobs.callerID
		calledJobs := callerToJobs.calledJobs
		callerJob := keyedJobs[callerJobID]

		// Find called jobs with no inputs or outputs and add caller job's inputs and outputs
		var noInputsList []string
		var noOutputsList []string
		for _, calledJob := range calledJobs {
			if len(calledJob.inputs) == 0 {
				noInputsList = append(noInputsList, calledJob.ID)
				if len(callerJob.inputs) > 0 {
					calledJob.inputs = make([]string, len(callerJob.inputs))
					copy(calledJob.inputs, callerJob.inputs)
				}

			}
			if len(calledJob.outputs) == 0 {
				noOutputsList = append(noOutputsList, calledJob.ID)
				if len(callerJob.outputs) > 0 {
					calledJob.outputs = make([]string, len(callerJob.outputs))
					copy(calledJob.outputs, callerJob.outputs)
				}
			}
		}

		// Remove callerJob from other jobs' inputs or outputs and add the appropriate called jobs
		for _, input := range callerJob.inputs {
			inputKey := strings.ToLower(input)
			job := keyedJobs[inputKey]
			for i, output := range job.outputs {
				if strings.EqualFold(output, callerJobID) {
					job.outputs = append(job.outputs[:i], job.outputs[i+1:]...)
					break
				}
			}
			job.outputs = append(job.outputs, noInputsList...)
		}
		for _, output := range callerJob.outputs {
			outputKey := strings.ToLower(output)
			job := keyedJobs[outputKey]
			for i, input := range job.inputs {
				if strings.EqualFold(input, callerJobID) {
					job.inputs = append(job.inputs[:i], job.inputs[i+1:]...)
					break
				}
			}
			job.inputs = append(job.inputs, noOutputsList...)
		}

		// Remove callerJob
		for i, job := range jobs {
			if strings.EqualFold(job.ID, callerJobID) {
				jobs = append(jobs[:i], jobs[i+1:]...)
			}
		}
		jobs = append(jobs, calledJobs...)
	}

	sort.Slice(jobs, func(i, j int) bool {
		ij := jobs[i]
		jj := jobs[j]
		return ij.ID < jj.ID
	})

	return jobs, nil
}
