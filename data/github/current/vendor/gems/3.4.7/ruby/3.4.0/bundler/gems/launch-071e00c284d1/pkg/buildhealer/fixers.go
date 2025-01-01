package buildhealer

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/constants"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/build"
)

type checkSuiteFixer interface {
	String() string
	LoggingFields() []kvp.Field
	Fix(context.Context, github.Client, WorkflowInfo, *github.CheckSuiteInfo) (build.WorkflowState, bool, error)
}

// Check suite that is already completed, nothing to do here so we just return cleanly
type checkSuiteAlreadyCompleted struct {
	conclusion string
}

func (cs *checkSuiteAlreadyCompleted) String() string             { return "already_completed" }
func (cs *checkSuiteAlreadyCompleted) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (cs *checkSuiteAlreadyCompleted) Fix(_ context.Context, _ github.Client, _ WorkflowInfo, _ *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	return getBuildState(cs.conclusion), false, nil
}

// checkSuiteNoCheckRuns fixes a check suite that has no check runs in it, it creates a check run marked "failed"
// with a message, and then updates the check suite state to completed.
type checkSuiteNoCheckRuns struct {
	conclusion string
	reason     HealReason
}

func (cs *checkSuiteNoCheckRuns) String() string             { return "no_check_runs" }
func (cs *checkSuiteNoCheckRuns) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (cs *checkSuiteNoCheckRuns) Fix(ctx context.Context, c github.Client, w WorkflowInfo, state *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	// Create a check run with some messaging
	t := time.Now()
	_, err := c.CreateCheckRun(ctx, github.CreateCheckRunRequest{
		Name:         getCheckRunName(cs.conclusion),
		Output:       getCheckRunOutput(w.WorkflowFilePath, cs.reason),
		Status:       string(github.CheckRunCompletedStatus),
		Conclusion:   string(getCheckRunConclusion(cs.conclusion)),
		ExternalID:   "github-actions",
		CompletedAt:  &t,
		RepositoryID: w.RepositoryID,
		CheckSuiteID: w.CheckSuiteID,
		HeadSHA:      types.CommitSha(state.SHA),
	})
	if err != nil {
		return build.WorkflowStateFailed, false, err
	}

	return getBuildState(cs.conclusion), true, updateCheckSuite(ctx, getCheckSuiteConclusion(cs.conclusion), c, w)
}

// checkSuiteAllRunsComplete has runs that are all marked complete, so what we need to do
// is calculate what status to set the suite to from the "least" status on the runs, and then
// apply that.
type checkSuiteAllRunsComplete struct {
	conclusion string
}

func (cs *checkSuiteAllRunsComplete) String() string             { return "all_runs_complete" }
func (cs *checkSuiteAllRunsComplete) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (cs *checkSuiteAllRunsComplete) Fix(ctx context.Context, c github.Client, w WorkflowInfo, state *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	return getBuildState(cs.conclusion), true, updateCheckSuite(ctx, rollupCheckRunConclusions(state.CheckRuns), c, w)
}

// checkSuiteSomeRunsIncomplete marks any incomplete runs on the check suite
// as completed/cancelled, including marking incomplete steps on those runs
// as completed/cancelled too.
type checkSuiteSomeRunsIncomplete struct {
	incompleteRunsCount int
	conclusion          string
	reason              HealReason
}

func (cs *checkSuiteSomeRunsIncomplete) String() string { return "some_runs_complete" }
func (cs *checkSuiteSomeRunsIncomplete) LoggingFields() []kvp.Field {
	return []kvp.Field{kvp.Int("gh.launch.check_suite_incomplete_runs_count", cs.incompleteRunsCount)}
}
func (cs *checkSuiteSomeRunsIncomplete) Fix(ctx context.Context, c github.Client, w WorkflowInfo, state *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	for _, cr := range state.CheckRuns {
		if cr.Status != string(github.CheckRunCompletedStatus) {
			steps := make([]github.CheckStepData, 0, len(cr.Steps))
			for _, step := range cr.Steps {
				if step.Status != string(github.CheckStepCompletedStatus) {
					steps = append(steps, github.CheckStepData{
						Number:     step.Number,
						Status:     string(github.CheckStepCompletedStatus),
						Conclusion: string(github.CheckStepNeutralConclusion),
					})
				}
			}

			req := github.UpdateCheckRunRequest{
				CheckRunID:   types.NewGlobalID(ctx, cr.ID),
				RepositoryID: w.RepositoryID,
				CompletedAt:  cr.StartedAt,
				Status:       string(github.CheckRunCompletedStatus),
				Conclusion:   string(github.CheckRunNeutralConclusion),
				Number:       cr.Number,
				Steps:        steps,
				Output:       getCheckRunOutput(w.WorkflowFilePath, cs.reason),
			}

			res, err := c.UpdateCheckRun(ctx, req)
			if err != nil {
				return build.WorkflowStateFailed, false, err
			}
			if res.CheckRunIDPair.IsZeroValue() {
				return build.WorkflowStateFailed, false, errors.New("CheckRunIDPair not found in output")
			}
		}
	}
	return getBuildState(cs.conclusion), true, updateCheckSuite(ctx, getCheckSuiteConclusion(cs.conclusion), c, w)
}

// Repository is disabled, nothing to do at all.
type repositoryDisabled struct{}

func (r *repositoryDisabled) String() string             { return "repo_disabled" }
func (r *repositoryDisabled) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (r *repositoryDisabled) Fix(_ context.Context, _ github.Client, _ WorkflowInfo, _ *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	return build.WorkflowStateCanceled, false, nil
}

// No check suite exists, nothing to do at all.
type checkSuiteMissing struct{}

func (cs *checkSuiteMissing) String() string             { return "check_suite_missing" }
func (cs *checkSuiteMissing) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (cs *checkSuiteMissing) Fix(_ context.Context, _ github.Client, _ WorkflowInfo, _ *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	return build.WorkflowStateNeverStarted, false, nil
}

// Workflow run and check suite deleted, nothing to do at all.
type workflowRunDeleted struct{}

func (cs *workflowRunDeleted) String() string             { return "workflow_run_deleted" }
func (cs *workflowRunDeleted) LoggingFields() []kvp.Field { return []kvp.Field{} }
func (cs *workflowRunDeleted) Fix(_ context.Context, _ github.Client, _ WorkflowInfo, _ *github.CheckSuiteInfo) (build.WorkflowState, bool, error) {
	return build.WorkflowStateCanceled, false, nil
}

func getCheckRunOutput(path string, reason HealReason) *github.CheckRunOutput {
	switch reason {
	case ReasonManual:
		return &github.CheckRunOutput{
			Title:   "Run manually canceled",
			Summary: "Run manually canceled.",
			Annotations: []github.CheckRunAnnotation{
				{
					AnnotationLevel: "FAILURE",
					Message:         "This run was manually canceled.",
					Path:            path,
					Location: github.CheckAnnotationRange{
						StartLine: 1,
						EndLine:   1,
					},
				},
			},
		}
	case ReasonScheduled:
		return &github.CheckRunOutput{
			Title:   "Run timed out",
			Summary: fmt.Sprintf("Run timed out after > %d days", constants.WorkflowMaxRunTimeDays),
			Annotations: []github.CheckRunAnnotation{
				{
					AnnotationLevel: "FAILURE",
					Message:         fmt.Sprintf("This run timed out after more than %d days.", constants.WorkflowMaxRunTimeDays),
					Path:            path,
					Location: github.CheckAnnotationRange{
						StartLine: 1,
						EndLine:   1,
					},
				},
			},
		}
	default:
		return &github.CheckRunOutput{
			Title:   "Run canceled",
			Summary: "Run canceled.",
			Annotations: []github.CheckRunAnnotation{
				{
					AnnotationLevel: "FAILURE",
					Message:         "This run was canceled",
					Path:            path,
					Location: github.CheckAnnotationRange{
						StartLine: 1,
						EndLine:   1,
					},
				},
			},
		}
	}
}

func updateCheckSuite(ctx context.Context, conclusion github.CheckSuiteConclusion, c github.Client, w WorkflowInfo) error {
	csRes, err := c.UpdateCheckSuite(ctx, github.UpdateCheckSuiteRequest{
		RepositoryID: w.RepositoryID,
		CheckSuiteID: w.CheckSuiteID,
		Conclusion:   string(conclusion),
	})
	if err != nil {
		return err
	}
	if csRes == nil {
		return errors.New("did not get a response from updating check suite")
	}
	return nil
}

var checkRunConclusionLevels = map[github.CheckSuiteConclusion]int{
	github.CheckSuiteActionRequiredConclusion: 1,
	github.CheckSuiteStaleConclusion:          2,
	github.CheckSuiteTimedOutConclusion:       3,
	github.CheckSuiteFailureConclusion:        4,
	github.CheckSuiteCancelledConclusion:      5,
	github.CheckSuiteSuccessConclusion:        6,
}

// rollupCheckRunConclusions loops through all the passed in conclusions and
// finds the "worst" among them to return as a check suite conclusion, it is
// based off of what is being done in CheckSuite#calculate_rollup_conclusion
// in dotcom:
// https://github.com/github/github/blob/52be187b6402aa41981d595107b710b877bd4d00/app/models/check_suite.rb#L244
func rollupCheckRunConclusions(crs []github.CheckRunInfo) github.CheckSuiteConclusion {
	out := github.CheckSuiteSuccessConclusion
	currVal := checkRunConclusionLevels[out]

	for _, run := range crs {
		// We are converting from a CheckRunConclusion to a CheckSuiteConclusion here basically,
		// and for some reason we have CheckSuiteConclusions in lower case in the constants, so
		// we need to run strings.ToLower to make sure we match correctly.
		conclusion := github.CheckSuiteConclusion(strings.ToLower(run.Conclusion))
		val, ok := checkRunConclusionLevels[conclusion]
		if !ok {
			continue
		}
		if val < currVal {
			currVal = val
			out = conclusion
		}
	}
	return out
}

type stateTypes struct {
	build build.WorkflowState
	run   github.CheckRunConclusion
	suite github.CheckSuiteConclusion
	name  string
}

var conclusionToStates = map[string]stateTypes{
	azptypes.ResultCanceled: {
		build: build.WorkflowStateCanceled,
		run:   github.CheckRunCancelledConclusion,
		suite: github.CheckSuiteCancelledConclusion,
		name:  "Build cancelled",
	},
	azptypes.ResultFailed: {
		build: build.WorkflowStateFailed,
		run:   github.CheckRunFailedConclusion,
		suite: github.CheckSuiteFailureConclusion,
		name:  "Build failed",
	},
	azptypes.ResultNone: {
		build: build.WorkflowStateNone,
		run:   github.CheckRunNeutralConclusion,
		suite: github.CheckSuiteNeutralConclusion,
		name:  "Build result neutral",
	},
	azptypes.ResultSkipped: {
		build: build.WorkflowStateSkipped,
		run:   github.CheckRunSkippedConclusion,
		suite: github.CheckSuiteSkippedConclusion,
		name:  "Build skipped",
	},
	azptypes.ResultPartiallySucceeded: {
		build: build.WorkflowStateSucceeded,
		run:   github.CheckRunSuccessConclusion,
		suite: github.CheckSuiteSuccessConclusion,
		name:  "Build partially succeeded",
	},
	azptypes.ResultSucceeded: {
		build: build.WorkflowStateSucceeded,
		run:   github.CheckRunSuccessConclusion,
		suite: github.CheckSuiteSuccessConclusion,
		name:  "Build succeeded",
	},
}

func getBuildState(conclusion string) build.WorkflowState {
	res, ok := conclusionToStates[conclusion]
	if !ok {
		return build.WorkflowStateNone
	}
	return res.build
}

func getCheckRunConclusion(conclusion string) github.CheckRunConclusion {
	res, ok := conclusionToStates[conclusion]
	if !ok {
		return github.CheckRunNeutralConclusion
	}
	return res.run
}

func getCheckSuiteConclusion(conclusion string) github.CheckSuiteConclusion {
	res, ok := conclusionToStates[conclusion]
	if !ok {
		return github.CheckSuiteNeutralConclusion
	}
	return res.suite
}

func getCheckRunName(conclusion string) string {
	res, ok := conclusionToStates[conclusion]
	if !ok {
		return "Build timed out"
	}
	return res.name
}
