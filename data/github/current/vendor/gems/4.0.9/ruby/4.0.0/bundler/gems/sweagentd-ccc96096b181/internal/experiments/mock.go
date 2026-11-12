package experiments

import (
	"context"

	v1 "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
)

var _ Client = &MockClient{}

// MockClient is a mock implementation of the Client interface for testing.
type MockClient struct {
	MockTrafficFilters TrafficFilters
	MockError          error
	MockAssignment     *Assignment
	MockOK             bool

	// Calls
	getFeatureAssignmentCalls []GetFeatureAssignmentCall
}

// GetFeatureAssignmentCall represents a single call to GetFeatureAssignment for testing purposes.
type GetFeatureAssignmentCall struct {
	ctx               context.Context
	featureName       string
	randomizationUnit *TrafficFilter
	trafficFilters    TrafficFilters
	assignment        *Assignment
	ok                bool
}

// NewTrafficFiltersDefaults returns mock traffic filters for testing.
func (e *MockClient) NewTrafficFiltersDefaults(ctx context.Context, twirpClient githubtwirp.ClientInterface, defaultFilters *FilterProps) (TrafficFilters, error) {
	return e.MockTrafficFilters, e.MockError
}

// GetFeatureAssignment returns a mock feature assignment for testing.
func (e *MockClient) GetFeatureAssignment(ctx context.Context, featureName string, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (*Assignment, bool) {
	e.getFeatureAssignmentCalls = append(e.getFeatureAssignmentCalls, GetFeatureAssignmentCall{
		ctx:               ctx,
		featureName:       featureName,
		randomizationUnit: randomizationUnit,
		trafficFilters:    trafficFilters,
		assignment:        e.MockAssignment,
		ok:                e.MockOK,
	})
	return e.MockAssignment, e.MockOK
}

// GetFeatureAssignmentCalled returns true if GetFeatureAssignment was called.
func (e *MockClient) GetFeatureAssignmentCalled() bool {
	return e.GetFeatureAssignmentCalledTimes() > 0
}

// GetFeatureAssignmentCalledTimes returns the number of times GetFeatureAssignment was called.
func (e *MockClient) GetFeatureAssignmentCalledTimes() int {
	return len(e.getFeatureAssignmentCalls)
}

// GetFeatureAssignmentCalledWithFeatureName returns true if GetFeatureAssignment was called with the given feature name.
func (e *MockClient) GetFeatureAssignmentCalledWithFeatureName(featureName string) bool {
	for _, call := range e.getFeatureAssignmentCalls {
		if call.featureName == featureName {
			return true
		}
	}
	return false
}

// MockTwirpClient is a mock implementation of the TwirpClient interface for testing.
type MockTwirpClient struct {
	MockOrgs []*v1.CopilotOrganization
	MockErr  error
}

// GetCopilotUser returns a mock copilot user for testing.
func (tc *MockTwirpClient) GetCopilotUser(ctx context.Context, req *v1.GetCopilotUserRequest) (*v1.GetCopilotUserResponse, error) {
	return &v1.GetCopilotUserResponse{
		UserDetails: &v1.CopilotUserDetails{
			CopilotOrganizations: tc.MockOrgs,
		},
	}, tc.MockErr
}
