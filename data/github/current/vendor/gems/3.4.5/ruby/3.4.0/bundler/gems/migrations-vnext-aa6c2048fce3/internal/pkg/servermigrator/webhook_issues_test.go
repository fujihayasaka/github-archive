package servermigrator

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/pointer"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

func TestServerMigrator_handleIssuesWebhook(t *testing.T) {
	type fields struct {
		clientSetup func(api *MockMigrationTargetAPI)
	}
	type args struct {
		guid string
		e    *github.IssuesEvent
	}
	tests := []struct {
		name    string
		fields  fields
		args    args
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should create a new issue and author",
			fields: fields{
				clientSetup: func(api *MockMigrationTargetAPI) {
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_Mannequin{
								Mannequin: &v1.Mannequin{
									ResourceId:    "http://github.test/monalisa",
									OrgResourceId: "http://github.test/acme",
								},
							},
						},
					}).Return(nil, nil)
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_Issue{
								Issue: &v1.Issue{
									ResourceId:           "http://github.test/test-org/test-repo/issues/1",
									UserResourceId:       "http://github.test/monalisa",
									AssigneesResourceIds: make([]string, 0),
								},
							},
						},
					}).Return(nil, nil)
				},
			},
			args: args{
				guid: "test-guid",
				e: &github.IssuesEvent{
					Action: pointer.Of("opened"),
					Issue: &github.Issue{
						HTMLURL: github.String("http://github.test/test-org/test-repo/issues/1"),
						User:    &github.User{HTMLURL: github.String("http://github.test/monalisa")},
					},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockMigration := NewMockMigrationTargetAPI(t)
			if tt.fields.clientSetup != nil {
				tt.fields.clientSetup(mockMigration)
			}
			m := &ServerMigrator{
				logger:          log.NewNullLogger(),
				migrationClient: mockMigration,
				statter:         stats.NullStatter,
				org:             "http://github.test/acme",
			}
			tt.wantErr(t, m.handleIssuesWebhook(context.Background(), tt.args.guid, tt.args.e), fmt.Sprintf("handleIssuesWebhook(%v, %v)", tt.args.guid, tt.args.e))
		})
	}
}

func TestServerMigrator_handleIssueCommentsWebhook(t *testing.T) {
	type fields struct {
		clientSetup func(api *MockMigrationTargetAPI)
	}
	type args struct {
		guid string
		e    *github.IssueCommentEvent
	}
	tests := []struct {
		name    string
		fields  fields
		args    args
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "should create a new issue comment and author",
			fields: fields{
				clientSetup: func(api *MockMigrationTargetAPI) {
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_Mannequin{
								Mannequin: &v1.Mannequin{
									ResourceId:    "http://github.test/monalisa",
									OrgResourceId: "http://github.test/acme",
								},
							},
						},
					}).Return(nil, nil)
					api.On("SendResources", mock.Anything, "", []*v1.Resource{
						{
							Resource: &v1.Resource_IssueComment{
								IssueComment: &v1.IssueComment{
									ResourceId:     "http://github.test/test-org/test-repo/issues/1#issuecomment-1",
									UserResourceId: "http://github.test/monalisa",
								},
							},
						},
					}).Return(nil, nil)
				},
			},
			args: args{
				guid: "test-guid",
				e: &github.IssueCommentEvent{
					Action: pointer.Of("created"),
					Comment: &github.IssueComment{
						HTMLURL: github.String("http://github.test/test-org/test-repo/issues/1#issuecomment-1"),
						User:    &github.User{HTMLURL: github.String("http://github.test/monalisa")},
					},
				},
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockMigration := NewMockMigrationTargetAPI(t)
			if tt.fields.clientSetup != nil {
				tt.fields.clientSetup(mockMigration)
			}
			m := &ServerMigrator{
				logger:          log.NewNullLogger(),
				migrationClient: mockMigration,
				statter:         stats.NullStatter,
				org:             "http://github.test/acme",
			}
			tt.wantErr(t, m.handleIssueCommentWebhook(context.Background(), tt.args.guid, tt.args.e), fmt.Sprintf("handleIssueCommentWebhook(%v, %v)", tt.args.guid, tt.args.e))
		})
	}
}
