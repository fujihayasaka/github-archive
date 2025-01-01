package github

import (
	"context"
	"time"

	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
)

type StepInfo struct {
	Number     int64
	Status     string
	Conclusion string
}

type CheckRunInfo struct {
	ID         string
	Status     string
	Conclusion string
	StartedAt  *time.Time
	Steps      []StepInfo
	Number     int64
}

type CheckSuiteInfo struct {
	Status       string
	Conclusion   string
	SHA          string
	NumCheckRuns int64
	CheckRuns    []CheckRunInfo
}

type checkSuiteQuery struct {
	Node struct {
		CheckSuite struct {
			Status     string
			Conclusion string
			Commit     struct {
				OID string
			}
			CheckRuns struct {
				TotalCount int64
				Nodes      []struct {
					ID         string
					Status     string
					Conclusion string
					StartedAt  *time.Time
					Number     int64
					Steps      struct {
						TotalCount int64
						Nodes      []struct {
							Number     int64
							Status     string
							Conclusion string
						}
					} `graphql:"steps(first:100)"`
				}
			} `graphql:"checkRuns(first: 100)"`
		} `graphql:"... on CheckSuite"`
	} `graphql:"node(id: $id)"`
}

func (c *client) GetCheckSuiteFromDotcom(ctx context.Context, checkSuiteID types.GlobalID) (*CheckSuiteInfo, error) {
	query := &checkSuiteQuery{}
	variables := map[string]any{"id": checkSuiteID.String()}

	err := c.strictQuery(ctx, "GetCheckSuiteForHealing", "query", query, variables)
	if _, isNotFoundError := err.(*terrors.NotFoundError); isNotFoundError {
		// Workflow run and associated check suite may have been deleted, let's no op instead of failing
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	suite := query.Node.CheckSuite
	runs := make([]CheckRunInfo, 0, suite.CheckRuns.TotalCount)
	for _, run := range suite.CheckRuns.Nodes {
		steps := make([]StepInfo, 0, run.Steps.TotalCount)
		for _, step := range run.Steps.Nodes {
			steps = append(steps, StepInfo{
				Number:     step.Number,
				Status:     step.Status,
				Conclusion: step.Conclusion,
			})
		}
		runs = append(runs, CheckRunInfo{
			ID:         run.ID,
			Status:     run.Status,
			Conclusion: run.Conclusion,
			StartedAt:  run.StartedAt,
			Steps:      steps,
		})
	}

	return &CheckSuiteInfo{
		Status:       suite.Status,
		Conclusion:   suite.Conclusion,
		SHA:          suite.Commit.OID,
		NumCheckRuns: suite.CheckRuns.TotalCount,
		CheckRuns:    runs,
	}, nil
}
