package executiongraph

import (
	"fmt"
	"sort"
	"strings"
)

// ExecutionGraph describes the structure of a workflow execution before it's run
type ExecutionGraph struct {
	Stages []Stage `json:"stages"`
}

// Stage is a grouping of groups of jobs that can be happening in parallel
type Stage struct {
	Groups []Group `json:"groups"`
}

// Group represents an array of jobs that have the same inputs and outputs
type Group struct {
	// ID is the unique identifier of the group
	ID string `json:"id"`

	// Name is the name of a group, useful for a matrix group
	Name string `json:"name,omitempty"`

	Type GroupType `json:"type"`

	// Jobs are the jobs in this group, could be empty if the jobs aren't known yet (e.g., a matrix group)
	Jobs []*Job `json:"jobs,omitempty"`

	// Inputs are a list of group IDs this group depends on, can be empty
	Inputs []string `json:"inputs,omitempty"`

	// Outputs are a list of group IDs depending on this group, can be empty
	Outputs []string `json:"outputs,omitempty"`
}

func (g *Group) addJob(j *Job) {
	g.Jobs = append(g.Jobs, j)
	sort.SliceStable(g.Jobs, func(i, j int) bool { return g.Jobs[i].ID < g.Jobs[j].ID })
}

func (g *Group) addInput(new string) {
	for _, existing := range g.Inputs {
		if new == existing {
			return
		}
	}
	g.Inputs = append(g.Inputs, new)
	sort.Strings(g.Inputs)
}

func (g *Group) addOutput(new string) {
	for _, existing := range g.Outputs {
		if new == existing {
			return
		}
	}
	g.Outputs = append(g.Outputs, new)
	sort.Strings(g.Outputs)
}

// GroupType determines the type of a group
type GroupType int

const (
	// GroupTypeDefault is the default type for a group, can contain one or more jobs
	GroupTypeDefault GroupType = iota

	// GroupTypeMatrix groups represent a single matrix job
	GroupTypeMatrix

	// GroupTypeStrategyExpression represents a single job whose strategy is generated from a workflow expression
	GroupTypeStrategyExpression

	// GroupTypeWorkflowMatrix groups represent a single matrix job that calls another workflow with a matrix
	GroupTypeWorkflowMatrix
)

// Job is one individual job being run
type Job struct {
	// ID is the unique identifier for this job
	ID string `json:"id"`

	// Name is the display name for this job
	Name *string `json:"name,omitempty"`

	isMatrix             bool
	isStrategyExpression bool
	isWorkflowMatrix     bool
	environmentID        string

	inputs  []string
	outputs []string
}

func (j *Job) addOutput(o string) {
	j.outputs = append(j.outputs, o)
	sort.Strings(j.outputs)
}

func (j *Job) needsNeededKey() string {
	var matrixName string
	if j.isMatrix || j.isStrategyExpression {
		matrixName = fmt.Sprintf("-%s-|", j.ID)
	}

	// Use environment for grouping
	var environmentName string
	if j.environmentID != "" {
		environmentName = fmt.Sprintf("%s|", j.environmentID)
	}

	return strings.ToLower(fmt.Sprintf("%s|%s%s%s", strings.Join(j.inputs, "&"), environmentName, matrixName, strings.Join(j.outputs, "&")))
}

func (j *Job) nameOrID() string {
	if j.Name != nil {
		return *j.Name
	}
	return j.ID
}
