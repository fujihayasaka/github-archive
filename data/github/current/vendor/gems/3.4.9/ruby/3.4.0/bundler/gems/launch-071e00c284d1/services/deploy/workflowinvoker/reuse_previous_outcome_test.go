package workflowinvoker

import (
	"context"
	goerr "errors"

	"github.com/stretchr/testify/mock"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/types"
)

func (s *buildInvokerTest) TestReusePreviousOutcomeCheck() {
	tests := []struct {
		name                  string
		event                 string
		expectedTreeId        types.CommitSha
		isError               bool
		hasReusableCheckSuite bool
		reusableCheckSuiteID  types.GlobalID
	}{
		{
			name:                  "Push event with reusable check suite",
			event:                 "push",
			expectedTreeId:        types.CommitSha("123"),
			isError:               false,
			hasReusableCheckSuite: true,
			reusableCheckSuiteID:  types.GlobalID("check-suite-1-clone-me"),
		},
		{
			name:                  "Push event without reusable check suite",
			event:                 "push",
			expectedTreeId:        types.CommitSha("123"),
			isError:               false,
			hasReusableCheckSuite: false,
		},
		{
			name:                  "Pull request with reusable check suite",
			event:                 "pull_request",
			expectedTreeId:        types.CommitSha("123"),
			isError:               false,
			hasReusableCheckSuite: true,
			reusableCheckSuiteID:  types.GlobalID("check-suite-1-clone-me"),
		},
		{
			name:                  "Merge group with reusable check suite",
			event:                 "merge_group",
			expectedTreeId:        types.CommitSha("123"),
			isError:               false,
			hasReusableCheckSuite: true,
			reusableCheckSuiteID:  types.GlobalID("check-suite-1-clone-me"),
		},
		{
			name:                  "Non matching event gets rejected",
			event:                 "workflow_dispatch",
			expectedTreeId:        types.CommitShaZeroValue,
			isError:               false,
			hasReusableCheckSuite: false,
		},
		{
			name:                  "Errors corretly surface",
			event:                 "push",
			expectedTreeId:        types.CommitShaZeroValue,
			isError:               true,
			hasReusableCheckSuite: false,
		},
	}
	for _, tt := range tests {
		s.Run(tt.name, func() {

			mockTwirpClient := &ghtwirp.MockClient{}
			if tt.isError {
				mockTwirpClient.On("FindTreeIDAndPreviousWorkflowRunToReuse", context.Background(), repoID, mock.Anything, mock.Anything, mock.Anything).Return(types.CommitShaZeroValue, nil, goerr.New("things go boom"))
			} else {
				if tt.hasReusableCheckSuite {
					reusableCheckSuite := &ghtwirp.ReusableCheckSuite{
						GlobalID: tt.reusableCheckSuiteID,
					}
					mockTwirpClient.On("FindTreeIDAndPreviousWorkflowRunToReuse", context.Background(), repoID, mock.Anything, mock.Anything, mock.Anything).Return(types.CommitSha("123"), reusableCheckSuite, nil)
				} else {
					mockTwirpClient.On("FindTreeIDAndPreviousWorkflowRunToReuse", context.Background(), repoID, mock.Anything, mock.Anything, mock.Anything).Return(types.CommitSha("123"), nil, nil)
				}
			}

			s.invoker.ghTwirpClient = mockTwirpClient
			treeId, reusableCheckSuite := s.invoker.reusePreviousOutcomeCheck(context.Background(), repoID, tt.event, ".github/workflows/test.yml", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef")

			s.Equal(tt.expectedTreeId, treeId)

			if tt.hasReusableCheckSuite {
				s.Equal(tt.reusableCheckSuiteID, reusableCheckSuite)
			} else {
				s.Equal(types.NilGlobalID, reusableCheckSuite)
			}
		})
	}
}
