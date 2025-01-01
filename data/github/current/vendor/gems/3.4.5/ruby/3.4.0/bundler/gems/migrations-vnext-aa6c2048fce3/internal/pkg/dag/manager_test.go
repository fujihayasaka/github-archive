package dag

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Returns a matcher function compatible with mock.MatchedBy. Returns true if
// `n` is a member of `options`.
func createIsNodeOneOfMatcher(options []Node) func(Node) bool {
	return func(n Node) bool {
		for _, o := range options {
			if n.ID == o.ID && n.Kind == o.Kind {
				return true
			}
		}
		return false
	}
}

func TestManagerImpl_AddEvent(t *testing.T) {
	event := &v1.Event{
		EventId:     "1",
		EventAction: v1.EventAction_EVENT_ACTION_EDITED,
		ResourceId:  "resource-123",
		Timestamp:   &timestamppb.Timestamp{Seconds: time.Now().Unix()},
		EventDetails: &v1.Event_PullRequestReviewCommentEvent{
			PullRequestReviewCommentEvent: &v1.PullRequestReviewCommentEventEdit{
				UserResourceId: "user-123",
			},
		},
		MigrationContext: &v1.MigrationContext{EnterpriseId: 1},
	}

	tests := map[string]struct {
		gets             *v1.Event
		setupDAGMock     func(m *MockDAG)
		setupManagerMock func(m *MockObjectStore)
		wantsErr         bool
		wantsErrSubstr   string
	}{
		"should return an error when an error occurs writing to the object store": {
			gets: event,
			setupManagerMock: func(m *MockObjectStore) {
				m.On("WritePayload", mock.IsType(context.Background()), "enterprise:1", "1", mock.Anything).Return(errors.New("store failure"))
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to store event payload",
		},
		"should return an error when the DAG fails to add the event node": {
			gets: event,
			setupDAGMock: func(d *MockDAG) {
				d.On("AddNode", mock.IsType(context.Background()), "enterprise:1", EventNode, ID("1"), mock.Anything, mock.Anything).Return(errors.New("test error"))
			},
			setupManagerMock: func(m *MockObjectStore) {
				m.On("WritePayload", mock.IsType(context.Background()), "enterprise:1", "1", mock.Anything).Return(nil)
			},
			wantsErr:       true,
			wantsErrSubstr: "error adding node to DAG",
		},
		"should store event successfully": {
			gets: event,
			setupDAGMock: func(d *MockDAG) {
				d.On("AddNode", mock.IsType(context.Background()), "enterprise:1", EventNode, ID("1"), Node{
					ID:   ID("resource-123"),
					Kind: ResourceNode,
				}, Node{ID: "user-123", Kind: ResourceNode},
				).Return(nil)
			},
			setupManagerMock: func(m *MockObjectStore) {
				m.On("WritePayload", mock.IsType(context.Background()), "enterprise:1", "1", mock.Anything).Return(nil)
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			mockDAG := NewMockDAG(t)
			objStore := NewMockObjectStore(t)

			if test.setupDAGMock != nil {
				test.setupDAGMock(mockDAG)
			}
			if test.setupManagerMock != nil {
				test.setupManagerMock(objStore)
			}
			m := &managerImpl{
				dag:         mockDAG,
				objectStore: objStore,
				logger:      log.NewNullLogger(),
			}

			err := m.AddEvent(context.Background(), test.gets)
			require.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			}
			mockDAG.AssertExpectations(t)
			objStore.AssertExpectations(t)
		})
	}
}

func TestManagerImpl_AddResource(t *testing.T) {
	validIssueResource := &v1.Issue{
		Body:           "Foo bar baz",
		ResourceId:     "http://github.dev/acme/widgets/issues/3",
		Title:          "Test issue",
		UserResourceId: "http://github.dev/monalisa",
	}

	tests := map[string]struct {
		dagMockSetup         func(d *MockDAG)
		gets                 *v1.Resource
		objectStoreMockSetup func(o *MockObjectStore, expectedPayload []byte)
		wantsErr             bool
		wantsErrSubstr       string
	}{
		"should return an error when WritePayload returns an error": {
			gets: &v1.Resource{Resource: &v1.Resource_Issue{Issue: validIssueResource}, MigrationContext: &v1.MigrationContext{EnterpriseId: 1}},
			objectStoreMockSetup: func(o *MockObjectStore, expectedPayload []byte) {
				o.On("WritePayload", mock.Anything, "enterprise:1", mock.Anything, mock.Anything).Return(errors.New("test error"))
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to store payload",
		},
		"should return an error when AddNode returns an error": {
			dagMockSetup: func(d *MockDAG) {
				d.On("AddNode", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(errors.New("test error"))
			},
			gets: &v1.Resource{Resource: &v1.Resource_Issue{Issue: validIssueResource}, MigrationContext: &v1.MigrationContext{EnterpriseId: 1}},
			objectStoreMockSetup: func(o *MockObjectStore, _ []byte) {
				o.On("WritePayload", mock.Anything, "enterprise:1", mock.Anything, mock.Anything).Return(nil)
			},
			wantsErr:       true,
			wantsErrSubstr: "error adding node to DAG",
		},
		"should store the payload and write the object to the dag": {
			dagMockSetup: func(d *MockDAG) {
				nodes := []Node{
					{ID: ID("http://github.dev/acme/widgets"), Kind: ResourceNode},
					{ID: ID(validIssueResource.UserResourceId), Kind: ResourceNode},
				}
				d.On("AddNode", mock.IsType(context.Background()), "enterprise:1", ResourceNode, ID(validIssueResource.ResourceId),
					mock.MatchedBy(createIsNodeOneOfMatcher(nodes)),
					mock.MatchedBy(createIsNodeOneOfMatcher(nodes)),
				).Return(nil)
			},
			gets: &v1.Resource{Resource: &v1.Resource_Issue{Issue: validIssueResource}, MigrationContext: &v1.MigrationContext{EnterpriseId: 1}},
			objectStoreMockSetup: func(o *MockObjectStore, expectedPayload []byte) {
				o.On("WritePayload", mock.IsType(context.Background()), "enterprise:1", validIssueResource.ResourceId, expectedPayload).Return(nil)
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			// Setup mocks
			expectedPayload, err := proto.Marshal(test.gets)
			require.NoError(t, err)

			dag := NewMockDAG(t)
			objStore := NewMockObjectStore(t)
			if test.dagMockSetup != nil {
				test.dagMockSetup(dag)
			}
			if test.objectStoreMockSetup != nil {
				test.objectStoreMockSetup(objStore, expectedPayload)
			}

			mock.MatchedBy(func(nodes ...Node) bool {
				fmt.Println(nodes)
				return false
			})

			m := &managerImpl{
				dag:         dag,
				logger:      log.NewNullLogger(),
				objectStore: objStore,
			}

			err = m.AddResource(context.Background(), test.gets)

			dag.AssertExpectations(t)
			objStore.AssertExpectations(t)

			require.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			}
		})
	}
}
