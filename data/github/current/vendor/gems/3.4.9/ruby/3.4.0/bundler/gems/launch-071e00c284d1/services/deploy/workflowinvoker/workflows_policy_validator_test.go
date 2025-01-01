package workflowinvoker

import (
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/workflowparser"
)

func TestWorkflowsToString(t *testing.T) {
	tests := []struct {
		Description string
		Workflows   map[string]workflowparser.CalledWorkflow
		Expected    int
		Error       error
	}{
		{
			Description: "calling depth 3",
			Workflows: map[string]workflowparser.CalledWorkflow{
				"calling-job-A": {
					Workflow: workflowparser.Workflow{
						Path: "github/public-server/.github/workflows/B.yml@main",
						CalledWorkflows: map[string]workflowparser.CalledWorkflow{
							"calling-job-B": {
								Workflow: workflowparser.Workflow{
									Path: "github/internal-server/.github/workflows/C.yml@main",
									CalledWorkflows: map[string]workflowparser.CalledWorkflow{
										"calling-job-C": {
											Workflow: workflowparser.Workflow{
												Path:            "github/internal-server/.github/workflows/D.yml@7ea84539bbecf0dec631ec4e0d5180a1fe74a571",
												CalledWorkflows: nil,
											},
										},
									},
								},
							},
						},
					},
				},
			},
			Expected: 3,
		},
		{
			Description: "calling depth 3 with no duplicates",
			Workflows: map[string]workflowparser.CalledWorkflow{
				"calling-job-A": {
					Workflow: workflowparser.Workflow{
						Path: "github/public-server/.github/workflows/B.yml@main",
						CalledWorkflows: map[string]workflowparser.CalledWorkflow{
							"calling-job-B": {
								Workflow: workflowparser.Workflow{
									Path: "github/internal-server/.github/workflows/C.yml@main",
									CalledWorkflows: map[string]workflowparser.CalledWorkflow{
										"calling-job-C": {
											Workflow: workflowparser.Workflow{
												Path:            "github/internal-server/.github/workflows/D.yml@7ea84539bbecf0dec631ec4e0d5180a1fe74a571",
												CalledWorkflows: nil,
											},
										},
									},
								},
							},
							"calling-job-B-2": {
								Workflow: workflowparser.Workflow{
									Path: "github/internal-server/.github/workflows/C.yml@main",
									CalledWorkflows: map[string]workflowparser.CalledWorkflow{
										"calling-job-C": {
											Workflow: workflowparser.Workflow{
												Path:            "github/internal-server/.github/workflows/D.yml@7ea84539bbecf0dec631ec4e0d5180a1fe74a571",
												CalledWorkflows: nil,
											},
										},
									},
								},
							},
						},
					},
				},
			},
			Expected: 3,
		},
		{
			Description: "calling depth exceeds 3",
			Workflows: map[string]workflowparser.CalledWorkflow{
				"calling-job-A": {
					Workflow: workflowparser.Workflow{
						Path: "github/public-server/.github/workflows/B.yml@main",
						CalledWorkflows: map[string]workflowparser.CalledWorkflow{
							"calling-job-B": {
								Workflow: workflowparser.Workflow{
									Path: "github/internal-server/.github/workflows/C.yml@main",
									CalledWorkflows: map[string]workflowparser.CalledWorkflow{
										"calling-job-C": {
											Workflow: workflowparser.Workflow{
												Path: "github/internal-server/.github/workflows/D.yml@7ea84539bbecf0dec631ec4e0d5180a1fe74a571",
												CalledWorkflows: map[string]workflowparser.CalledWorkflow{
													"calling-job-D": {
														Workflow: workflowparser.Workflow{
															Path: "github/internal-server/.github/workflows/E.yml@main",
															CalledWorkflows: map[string]workflowparser.CalledWorkflow{
																"calling-job-E": {
																	Workflow: workflowparser.Workflow{
																		Path:            "github/internal-server/.github/workflows/F.yml@main",
																		CalledWorkflows: nil,
																	},
																},
															},
														},
													},
												},
											},
										},
									},
								},
							},
						},
					},
				},
			},
			Error: errors.New("max workflow call depth reached"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.Description, func(t *testing.T) {
			wfs, err := workflowsToString(tt.Workflows, 1)
			if tt.Error != nil {
				require.Error(t, err, tt.Error.Error())
			} else {
				require.NoError(t, err, "workflowsToString should not error")
				require.Equal(t, tt.Expected, len(wfs))
			}
		})
	}
}
