package workflowinvoker

import (
	"context"
	"crypto/sha1"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/pkg/errors"

	authzpb "github.com/github/authzd/pkg/proto"
	"github.com/github/go-log"
	blobs "github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	sTypes "github.com/github/spokes-proto/gen/go/v1/types"

	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	ghclient "github.com/github/launch/clients/github"
	"github.com/github/launch/clients/spokesd"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/model"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	ghactions "github.com/github/launch/proto/monolith/core/v1"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowparser"
)

var (
	FakeTenantID = "tenant-id"
	AltTenantID  = "00000000-0000-0000-0000-000000000000"

	// see https://ref45638.github.io/msgpack-converter/ to encode/decode
	FakeOwnerId1 types.GlobalID = "O_kgAB" // [0, 1]
	FakeRepoId1  types.GlobalID = "R_kgAB" // [0, 1]

	FakeOwnerId2 types.GlobalID = "O_kgAC" // [0, 2]
	FakeRepoId2  types.GlobalID = "R_kgAC" // [0, 2]

	FakeOwnerId3 types.GlobalID = "O_kgAD" // [0, 3]
	FakeRepoId3  types.GlobalID = "R_kgAD" // [0, 3]

)

func TestWorkflowSourceFactory(t *testing.T) {

	singleRepoResolver := newStubRepoMetadataResolver()
	singleRepoResolver.store(FakeOwnerId1, FakeRepoId1, "owner1", "repo1", FakeTenantID, false)

	dualRepoResolver := newStubRepoMetadataResolver()
	dualRepoResolver.store(FakeOwnerId1, FakeRepoId1, "owner1", "repo1", FakeTenantID, false)
	dualRepoResolver.store(FakeOwnerId2, FakeRepoId2, "owner2", "repo2", FakeTenantID, false)

	altRepoResolver := newStubRepoMetadataResolver()
	altRepoResolver.store(FakeOwnerId1, FakeRepoId1, "owner1", "repo1", FakeTenantID, false)
	altRepoResolver.store(FakeOwnerId2, FakeRepoId3, "owner2", "repo3", FakeTenantID, false)

	tests := []struct {
		desc string

		setupAuthzClient func() authzd.Client
		spokesdClient    spokesd.Client
		repoResolver     RepositoryMetadataResolver

		callerRepo                  *CallerRepo
		callerRepoMetadata          *workflowparser.RepositoryMetadata
		wfRef                       model.WorkflowRef
		invocationEvent             string
		previousReferencedWorkflows []workflowparser.ReferencedWorkflow
		expectedFile                *types.ResolvedFile
		expectedMeta                *workflowparser.RepositoryMetadata
		expectedOK                  bool
		expectedErr                 error
	}{
		{
			// if caller repo and called repo are same
			// we do not check the repo visibility so authzd is nil
			desc: "same repo workflow with nwo and branch",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@test-branch", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "same repo workflow with case insensitive nwo",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "Owner1",
				Repo:  "Repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			expectedFile: makeResolvedFile("Owner1/Repo1/.github/workflows/workflow1.yml@test-branch", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "Owner1/Repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "different public repo workflow with nwo and branch",
			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"3:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeaea366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {"bd308308d5a52f33da3f8e837bb5febeaea366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: altRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId3,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				DatabaseID: 3,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@test-branch", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeaea366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "different public repo workflow with case insensitive nwo and branch",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"3:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeaea366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {"bd308308d5a52f33da3f8e837bb5febeaea366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: altRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId3,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				DatabaseID: 3,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				RepositoryDatabaseID: 3,
			},
			wfRef: model.WorkflowRef{
				Owner: "owNer1",
				Repo:  "Repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: makeResolvedFile("owNer1/Repo1/.github/workflows/workflow1.yml@test-branch", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeaea366bb", "owNer1/Repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "different public repo workflow with nwo and without branch",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"3:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeaea366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {"bd308308d5a52f33da3f8e837bb5febeaea366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},

			repoResolver: altRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId3,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				DatabaseID: 3,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   "owner1",
				Repo:    "repo1",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  terrors.NewNotFoundError(errors.New("workflow version not provided")),
		},
		{
			desc: "different private repo",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"3:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeaea366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {"bd308308d5a52f33da3f8e837bb5febeaea366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: altRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId3,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				DatabaseID: 3,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeaea366bb"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeaea366bb", "hello world!", "", "bd308308d5a52f33da3f8e837bb5febeaea366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "different public repo workflow with nwo and invalid/forked sha",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"3:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {},
				},
			},
			repoResolver: altRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId3,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				DatabaseID: 3,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo3",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeaea366bb"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  nil,
		},
		{
			desc: "same repo workflow with nwo and incorrect branch",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeaea366bb",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("different-branch"),
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  terrors.NewNotFoundError(errors.New("reference to workflow should be either a valid branch, tag, or commit")),
		},
		{
			desc: "same repo incorrect workflow with nwo and branch",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			repoResolver: singleRepoResolver,
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/test-branch": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow2.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				}},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  terrors.NewNotFoundError(errors.New("workflow was not found.")),
		},
		{
			desc: "local workflow with nwo and without version",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/heads/test-branch",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   "owner1",
				Repo:    "repo1",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  terrors.NewNotFoundError(errors.New("workflow version not provided")),
		},
		{
			desc: "local workflow without nwo and without version for pull_request event with merge commit",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/pull/8/merge",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			invocationEvent: flowevents.PullRequest,
			expectedFile:    makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/pull/8/merge", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:      true,
			expectedErr:     nil,
		},
		{
			desc: "local workflow without nwo and without version for pull_request_review event with merge commit",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/pull/8/merge",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			invocationEvent: flowevents.PullRequestReview,
			expectedFile:    makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/pull/8/merge", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:      true,
			expectedErr:     nil,
		},
		{
			desc: "local workflow without nwo and without version for pull_request_review_comment event with merge commit",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/pull/8/merge",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			invocationEvent: flowevents.PullRequestReviewComment,
			expectedFile:    makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/pull/8/merge", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:      true,
			expectedErr:     nil,
		},
		{
			desc: "local workflow without nwo and without version for merge_group event with merge commit",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/heads/gh-readonly-queue/main/pr-1-2de9a809c6cc45056c470c8cc8426055f0f7461d",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			invocationEvent: flowevents.MergeGroup,
			expectedFile:    makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/heads/gh-readonly-queue/main/pr-1-2de9a809c6cc45056c470c8cc8426055f0f7461d", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:      true,
			expectedErr:     nil,
		},
		{
			desc: "local workflow without nwo and without version for non pull_request events",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/heads/test-branch",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "same repo workflow with nwo and sha",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "same repo incorrect workflow with nwo and sha",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  terrors.NewNotFoundError(errors.New("workflow was not found.")),
		},
		{
			desc: "resolved commit sha does not match",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {"cccc8308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeaea366bb"),
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  nil,
		},
		{
			desc: "no reachable commit sha",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {},
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeaea366bb"),
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  nil,
		},
		{
			desc: "too many reachable commit sha",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeaea366bb": {
						"bd308308d5a52f33da3f8e837bb5febeaea366bb", "bd308308d5a52f33da3f8e837bb5febeaea466bb"},
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeaea366bb"),
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  nil,
		},
		{
			desc: "tags",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/tags/release1": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("release1"),
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@release1", "hello world!", "refs/tags/release1", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "prioritizes tags over heads",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/release1": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
					"refs/tags/release1":  "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
				},
				byRepoCommit: map[string][]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef": {"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef:.github/workflows/workflow1.yml": "hello world!",
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "this is the wrong file!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("release1"),
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@release1", "hello world!", "refs/tags/release1", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "caller repo with global id",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"2:1": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/tags/release1": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
				},
				byRepoCommit: map[string][]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef": {"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
				},
				byRepoOIDPath: map[string]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: dualRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId2,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				DatabaseID: 2,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("release1"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryID:         FakeRepoId1,
				RepositoryDatabaseID: 1,
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@release1", "hello world!", "refs/tags/release1", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "branch ref with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@test-branch",
					Ref:  "refs/heads/test-branch",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@test-branch", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "tag ref with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-tag"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@test-tag",
					Ref:  "refs/tags/test-tag",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@test-tag", "hello world!", "refs/tags/test-tag", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "SHA ref with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "local ref with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				Ref: "refs/heads/test-branch",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner:   ".",
				Repo:    ".",
				Path:    ".github/workflows/workflow1.yml",
				Version: model.VersionRef{},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb",
					Ref:  "refs/heads/test-branch",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "refs/heads/test-branch", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner1/repo1"),
			expectedOK:   true,
			expectedErr:  nil,
		},
		{
			desc: "branch ref not found with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-branch"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@mismatch",
					Ref:  "refs/heads/mismatch",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  errors.New("workflow ref not found in previous attempt referenced workflows"),
		},
		{
			desc: "tag ref not found with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("test-tag"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@mismatch",
					Ref:  "refs/tags/mismatch",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  errors.New("workflow ref not found in previous attempt referenced workflows"),
		},
		{
			desc: "SHA ref not found with previous run attempt",

			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{},
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/workflow1.yml": "hello world!",
				},
			},
			repoResolver: singleRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
				RepositoryDatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner1",
				Repo:  "repo1",
				Path:  ".github/workflows/workflow1.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			previousReferencedWorkflows: []workflowparser.ReferencedWorkflow{
				{
					Path: "owner1/repo1/.github/workflows/workflow1.yml@mismatch",
					Sha:  "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
			},
			expectedFile: nil,
			expectedOK:   false,
			expectedErr:  errors.New("workflow ref not found in previous attempt referenced workflows"),
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()

			existingCheckSuiteID := types.NilGlobalID
			previousPlanID := uuid.Nil

			twirpClient := &ghtwirp.MockClient{}
			twirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, ghclient.ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag, mock.Anything).Return(true)

			if tt.expectedMeta != nil {
				twirpClient.On("FindRepositoriesByName", mock.Anything, []string{tt.wfRef.GetNWO().String()}).
					Return(makeRepositoriesInfoFromMetadata(bucket(tt.expectedMeta)), nil)
			}

			if len(tt.previousReferencedWorkflows) > 0 {
				existingCheckSuiteID = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 123))

				var err error
				previousPlanID, err = uuid.NewUUID()
				require.NoError(t, err)

				twirpClient.On("GetWorkflowRunExecution", mock.Anything, existingCheckSuiteID, previousPlanID).Return(
					&ghtwirp.WorkflowRunExecutionResponse{
						ReferencedWorkflows: tt.previousReferencedWorkflows,
					},
					err)
			}

			factory := SpokesdWorkflowSourceFactory(tt.setupAuthzClient(), tt.spokesdClient, twirpClient, log.NullLogger, observability.NewTestObservability())

			// defaulting to push event
			if tt.invocationEvent == "" {
				tt.invocationEvent = flowevents.Push
			}

			invocationEvent := InvokingEvent{
				Name: tt.invocationEvent,
			}

			wfSrc := factory.Build(ctx, tt.repoResolver, tt.callerRepo, &invocationEvent, existingCheckSuiteID, previousPlanID)
			wfSrc.LoadPreviousRunAttemptInfo(ctx)
			gotFile, gotMeta, gotOK, gotErr := wfSrc.GetWorkflowFile(ctx, tt.wfRef, tt.callerRepoMetadata, 0)
			if tt.expectedErr != nil {
				require.EqualError(t, gotErr, tt.expectedErr.Error())
			} else {
				require.NoError(t, gotErr)
			}
			if tt.expectedOK == true {
				softCompareRepositoryMetadata(t, tt.expectedMeta, gotMeta)
			}
			require.Equal(t, tt.expectedOK, gotOK)
			require.Equal(t, tt.expectedFile, gotFile)
		})
	}
}

func TestWorkflowSourceFactory_Nested_SetCallerRepo(t *testing.T) {
	type nestedScenario struct {
		wfRef        model.WorkflowRef
		expectedFile *types.ResolvedFile
		expectedMeta *workflowparser.RepositoryMetadata
		expectedOK   bool
		expectedErr  error
	}

	initialRepoId := types.GlobalID("R_kgAq") // [0, 42]
	multiRepoResolver := newStubRepoMetadataResolver()
	multiRepoResolver.store(FakeOwnerId1, FakeRepoId1, "owner1", "repo1", FakeTenantID, false)
	multiRepoResolver.store(FakeOwnerId2, FakeRepoId2, "owner2", "repo2", FakeTenantID, false)
	multiRepoResolver.store(FakeOwnerId3, initialRepoId, "initial_owner", "initial_repo", FakeTenantID, false)

	tests := []struct {
		desc string

		setupAuthzClient func() authzd.Client
		spokesdClient    spokesd.Client
		repoResolver     RepositoryMetadataResolver
		invocationEvent  string

		callerRepo         *CallerRepo
		callerRepoMetadata *workflowparser.RepositoryMetadata
		nestedScenarios    []nestedScenario
	}{
		{
			desc: "caller repo with nwo in nested scenario",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"42:1": true,
						"42:2": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/tags/release1": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
					"refs/tags/release2": "adbeefdeadbeefdeadbeefdeadbeefdeadbeefde",
				},
				byRepoCommit: map[string][]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef": {"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
					"2:adbeefdeadbeefdeadbeefdeadbeefdeadbeefde": {"adbeefdeadbeefdeadbeefdeadbeefdeadbeefde"},
				},
				byRepoOIDPath: map[string]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef:.github/workflows/workflow1.yml": "hello world!",
					"2:adbeefdeadbeefdeadbeefdeadbeefdeadbeefde:.github/workflows/workflow2.yml": "mona lisa!",
				},
			},
			repoResolver: multiRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: initialRepoId,
				NWO: types.RepositoryFullName{
					Owner: "initial_owner",
					Name:  "initial_repo",
				},
				DatabaseID: 42,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "initial_owner",
					Name:  "initial_repo",
				},
				RepositoryDatabaseID: 42,
			},
			nestedScenarios: []nestedScenario{
				{
					wfRef: model.WorkflowRef{
						Owner: "owner1",
						Repo:  "repo1",
						Path:  ".github/workflows/workflow1.yml",
						Version: model.VersionRef{
							GitRef: pstring("release1"),
						},
					},
					expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@release1", "hello world!", "refs/tags/release1", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "owner1/repo1"),
					expectedMeta: &workflowparser.RepositoryMetadata{
						RepositoryDatabaseID: 1,
						RepositoryNWO: types.RepositoryFullName{
							Owner: "owner1",
							Name:  "repo1",
						},
						RepositoryID: FakeRepoId1,
					},
					expectedOK:  true,
					expectedErr: nil,
				},
				{
					wfRef: model.WorkflowRef{
						Owner: "owner2",
						Repo:  "repo2",
						Path:  ".github/workflows/workflow2.yml",
						Version: model.VersionRef{
							GitRef: pstring("release2"),
						},
					},
					expectedFile: makeResolvedFile("owner2/repo2/.github/workflows/workflow2.yml@release2", "mona lisa!", "refs/tags/release2", "adbeefdeadbeefdeadbeefdeadbeefdeadbeefde", "owner2/repo2"),
					expectedMeta: &workflowparser.RepositoryMetadata{
						RepositoryDatabaseID: 2,
						RepositoryNWO: types.RepositoryFullName{
							Owner: "owner2",
							Name:  "repo2",
						},
						RepositoryID: FakeRepoId2,
					},
					expectedOK:  true,
					expectedErr: nil,
				},
			},
		},
		{
			desc: "caller repo with global id in nested scenario",

			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"42:1": true,
						"42:2": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/tags/release1": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
					"refs/tags/release2": "adbeefdeadbeefdeadbeefdeadbeefdeadbeefde",
				},
				byRepoCommit: map[string][]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef": {"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"},
					"2:adbeefdeadbeefdeadbeefdeadbeefdeadbeefde": {"adbeefdeadbeefdeadbeefdeadbeefdeadbeefde"},
				},
				byRepoOIDPath: map[string]string{
					"1:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef:.github/workflows/workflow1.yml": "hello world!",
					"2:adbeefdeadbeefdeadbeefdeadbeefdeadbeefde:.github/workflows/workflow2.yml": "mona lisa!",
				},
			},
			repoResolver: multiRepoResolver,
			callerRepo: &CallerRepo{
				RepoID: initialRepoId,
				NWO: types.RepositoryFullName{
					Owner: "initial_owner",
					Name:  "initial_repo",
				},
				DatabaseID: 42,
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "initial_owner",
					Name:  "initial_repo",
				},
				RepositoryDatabaseID: 42,
			},
			nestedScenarios: []nestedScenario{
				{
					wfRef: model.WorkflowRef{
						Owner: "owner1",
						Repo:  "repo1",
						Path:  ".github/workflows/workflow1.yml",
						Version: model.VersionRef{
							GitRef: pstring("release1"),
						},
					},
					expectedFile: makeResolvedFile("owner1/repo1/.github/workflows/workflow1.yml@release1", "hello world!", "refs/tags/release1", "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "owner1/repo1"),
					expectedMeta: &workflowparser.RepositoryMetadata{
						RepositoryDatabaseID: 1,
						RepositoryNWO: types.RepositoryFullName{
							Owner: "owner1",
							Name:  "repo1",
						},
						RepositoryID: FakeRepoId1,
					},
					expectedOK:  true,
					expectedErr: nil,
				},
				{
					wfRef: model.WorkflowRef{
						Owner: "owner2",
						Repo:  "repo2",
						Path:  ".github/workflows/workflow2.yml",
						Version: model.VersionRef{
							GitRef: pstring("release2"),
						},
					},
					expectedFile: makeResolvedFile("owner2/repo2/.github/workflows/workflow2.yml@release2", "mona lisa!", "refs/tags/release2", "adbeefdeadbeefdeadbeefdeadbeefdeadbeefde", "owner2/repo2"),
					expectedMeta: &workflowparser.RepositoryMetadata{
						RepositoryDatabaseID: 2,
						RepositoryNWO: types.RepositoryFullName{
							Owner: "owner2", Name: "repo2",
						},
						RepositoryID: FakeRepoId2,
					},
					expectedOK:  true,
					expectedErr: nil,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()
			twirpClient := &ghtwirp.MockClient{}

			twirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, ghclient.ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag, mock.Anything).Return(true)

			factory := SpokesdWorkflowSourceFactory(tt.setupAuthzClient(), tt.spokesdClient, twirpClient, log.NullLogger, observability.NewTestObservability())

			// defaulting to push event
			if tt.invocationEvent == "" {
				tt.invocationEvent = flowevents.Push
			}

			invocationEvent := InvokingEvent{
				Name: tt.invocationEvent,
			}

			wfSrc := factory.Build(ctx, tt.repoResolver, tt.callerRepo, &invocationEvent, types.NilGlobalID, uuid.Nil)
			for _, nestedScenario := range tt.nestedScenarios {
				if nestedScenario.expectedMeta != nil {
					twirpClient.On("FindRepositoriesByName", mock.Anything, []string{nestedScenario.expectedMeta.RepositoryNWO.String()}).
						Return(makeRepositoriesInfoFromMetadata(bucket(nestedScenario.expectedMeta)), nil)
				}
				twirpClient.On("FindRepositoriesByName", mock.Anything, []string{tt.callerRepo.NWO.String()}).
					Return(makeRepositoriesInfo(bucket(tt.callerRepo)), nil)

				gotFile, gotMeta, gotOK, gotErr := wfSrc.GetWorkflowFile(ctx, nestedScenario.wfRef, tt.callerRepoMetadata, 0)
				if nestedScenario.expectedErr != nil {
					require.EqualError(t, gotErr, nestedScenario.expectedErr.Error())
				} else {
					require.NoError(t, gotErr)
					softCompareRepositoryMetadata(t, nestedScenario.expectedMeta, gotMeta)
				}
				require.Equal(t, nestedScenario.expectedOK, gotOK)
				require.Equal(t, nestedScenario.expectedFile, gotFile)
				wfSrc.SetCallerRepo(gotMeta.RepositoryID, gotMeta.RepositoryNWO, gotFile.Ref, gotFile.SHA)
			}
		})
	}
}

func TestWorkflowSourceFactory_UpdateCallerRepo_LocalWorkflows(t *testing.T) {

	tests := []struct {
		desc string

		setupAuthzClient func() authzd.Client
		spokesdClient    spokesd.Client
		repoResolver     RepositoryMetadataResolver

		initialCallerRepo  *CallerRepo
		callerRepo         *CallerRepo
		callerRepoMetadata *workflowparser.RepositoryMetadata
		wfRef              model.WorkflowRef
		invocationEvent    string
		expectedFile       *types.ResolvedFile
		expectedMeta       *workflowparser.RepositoryMetadata
		expectedOK         bool
		expectedErr        error
	}{
		{
			desc: "calling local workflow without nwo in new local context",
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"2:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				byRepoOIDPath: map[string]string{
					"2:bd308308d5a52f33da3f8e837bb5febeeaa366bb:.github/workflows/local_workflow.yml": "hello world!",
				},
			},
			setupAuthzClient: func() authzd.Client {
				return nil
			},
			repoResolver: newStubRepoMetadataResolverWithSeedData(t, FakeOwnerId2, FakeRepoId2, "owner2", "repo2", FakeTenantID, true),
			initialCallerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner1",
					Name:  "repo1",
				},
			},
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId2,
				NWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				Ref: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				SHA: "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
			},
			wfRef: model.WorkflowRef{
				Owner: ".",
				Repo:  ".",
				Path:  ".github/workflows/local_workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedFile: makeResolvedFile("owner2/repo2/.github/workflows/local_workflow.yml@bd308308d5a52f33da3f8e837bb5febeeaa366bb", "hello world!", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "bd308308d5a52f33da3f8e837bb5febeeaa366bb", "owner2/repo2"),
			expectedOK:   true,
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
			},
			expectedErr: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()

			twirpClient := &ghtwirp.MockClient{}
			twirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, ghclient.ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag, mock.Anything).Return(true)

			factory := SpokesdWorkflowSourceFactory(tt.setupAuthzClient(), tt.spokesdClient, twirpClient, log.NullLogger, observability.NewTestObservability())

			// defaulting to push event
			if tt.invocationEvent == "" {
				tt.invocationEvent = flowevents.Push
			}

			invocationEvent := InvokingEvent{
				Name: tt.invocationEvent,
			}

			wfSrc := factory.Build(ctx, tt.repoResolver, tt.initialCallerRepo, &invocationEvent, types.NilGlobalID, uuid.Nil)
			// change the repo
			wfSrc.SetCallerRepo(tt.callerRepo.RepoID, tt.callerRepo.NWO, tt.callerRepo.Ref, tt.callerRepo.SHA)
			gotFile, gotMeta, gotOK, gotErr := wfSrc.GetWorkflowFile(ctx, tt.wfRef, tt.callerRepoMetadata, 0)
			if tt.expectedErr != nil {
				require.EqualError(t, gotErr, tt.expectedErr.Error())
			} else {
				require.NoError(t, gotErr)
			}
			require.Equal(t, tt.expectedOK, gotOK)
			require.Equal(t, tt.expectedFile, gotFile)
			require.Equal(t, tt.expectedMeta, gotMeta)
		})
	}
}

func TestRepositoryMetadataFetcher(t *testing.T) {
	azpResource := &azptypes.BackingResources{
		CreationResult: azptypes.CreationResult{TenantID: FakeTenantID},
	}

	tests := []struct {
		desc        string
		repoID      types.GlobalID
		nwo         types.RepositoryFullName
		response    *github.BasicRepositoryInfo
		azpResource *azptypes.BackingResources
		azpGetErr   error
		metadata    *workflowparser.RepositoryMetadata
		err         error
		owner       types.GlobalID
	}{
		{
			desc:     "when the API call errors",
			repoID:   types.GlobalID("repo"),
			owner:    types.GlobalID("foo"),
			nwo:      types.RepositoryFullName{Name: "launch", Owner: "github"},
			response: nil,
			metadata: nil,
			err:      fmt.Errorf("an error occurred"),
		},
		{
			desc:        "when plan owners are the same",
			repoID:      types.GlobalID("repo"),
			owner:       types.GlobalID("github-ent"),
			nwo:         types.RepositoryFullName{Name: "launch", Owner: "github"},
			azpResource: azpResource,
			err:         nil,
			response: &github.BasicRepositoryInfo{
				ID:         types.GlobalID("repo"),
				DatabaseID: 1123,
				Name:       "launch",
				Owner:      github.BasicOwnerInfo{ID: types.GlobalID("github-org"), Name: "github"},
				PlanOwner:  github.BasicPlanOwnerInfo{ID: types.GlobalID("github-ent")},
			},
			metadata: &workflowparser.RepositoryMetadata{
				TenantID:             FakeTenantID,
				RepositoryNWO:        types.RepositoryFullName{Name: "launch", Owner: "github"},
				RepositoryID:         types.GlobalID("repo"),
				RepositoryDatabaseID: 1123,
				IsTrusted:            true,
				PlanOwnerID:          types.GlobalID("github-ent"),
			},
		},
		{
			desc:        "when plan owners are not the same",
			repoID:      types.GlobalID("repo"),
			owner:       types.GlobalID("not-github-ent"),
			nwo:         types.RepositoryFullName{Name: "launch", Owner: "github"},
			err:         nil,
			azpResource: azpResource,
			response: &github.BasicRepositoryInfo{
				ID:         types.GlobalID("repo"),
				DatabaseID: 1123,
				Name:       "launch",
				Owner:      github.BasicOwnerInfo{ID: types.GlobalID("github-org"), Name: "github"},
				PlanOwner:  github.BasicPlanOwnerInfo{ID: types.GlobalID("github-ent")},
			},
			metadata: &workflowparser.RepositoryMetadata{
				TenantID:             FakeTenantID,
				RepositoryNWO:        types.RepositoryFullName{Name: "launch", Owner: "github"},
				RepositoryID:         types.GlobalID("repo"),
				RepositoryDatabaseID: 1123,
				IsTrusted:            false,
				PlanOwnerID:          types.GlobalID("github-ent"),
			},
		},
		{
			desc:        "when plan owners are the same, but in different global id formats",
			repoID:      types.GlobalID("repo"),
			owner:       types.GlobalID("E_kgAB"),
			nwo:         types.RepositoryFullName{Name: "launch", Owner: "github"},
			err:         nil,
			azpResource: azpResource,
			response: &github.BasicRepositoryInfo{
				ID:         types.GlobalID("repo"),
				DatabaseID: 1123,
				Name:       "launch",
				Owner:      github.BasicOwnerInfo{ID: types.GlobalID("github-org"), Name: "github"},
				PlanOwner:  github.BasicPlanOwnerInfo{ID: types.GlobalID("MDEwOkVudGVycHJpc2Ux")},
			},
			metadata: &workflowparser.RepositoryMetadata{
				TenantID:             FakeTenantID,
				RepositoryNWO:        types.RepositoryFullName{Name: "launch", Owner: "github"},
				RepositoryID:         types.GlobalID("repo"),
				RepositoryDatabaseID: 1123,
				IsTrusted:            true,
				PlanOwnerID:          types.GlobalID("MDEwOkVudGVycHJpc2Ux"),
			},
		},
		{
			desc:        "when fetching tenant fails with a generic error",
			repoID:      types.GlobalID("repo"),
			owner:       types.GlobalID("not-github-ent"),
			nwo:         types.RepositoryFullName{Name: "launch", Owner: "github"},
			err:         fmt.Errorf("an error occurred"),
			azpResource: nil,
			azpGetErr:   fmt.Errorf("an error occurred"),
			response: &github.BasicRepositoryInfo{
				ID:         types.GlobalID("repo"),
				DatabaseID: 1123,
				Name:       "launch",
				Owner:      github.BasicOwnerInfo{ID: types.GlobalID("github-org"), Name: "github"},
				PlanOwner:  github.BasicPlanOwnerInfo{ID: types.GlobalID("github-ent")},
			},
		},
		{
			desc:        "when fetching tenant name fails with a GetAzpResourcesError",
			repoID:      types.GlobalID("repo"),
			owner:       types.GlobalID("not-github-ent"),
			nwo:         types.RepositoryFullName{Name: "launch", Owner: "github"},
			err:         nil,
			azpResource: nil,
			azpGetErr:   deployer.NewGetAzpResourcesError(types.GlobalID("repo")),
			response: &github.BasicRepositoryInfo{
				ID:         types.GlobalID("repo"),
				DatabaseID: 1123,
				Name:       "launch",
				Owner:      github.BasicOwnerInfo{ID: types.GlobalID("github-org"), Name: "github"},
				PlanOwner:  github.BasicPlanOwnerInfo{ID: types.GlobalID("github-ent")},
			},
			metadata: &workflowparser.RepositoryMetadata{
				TenantID:             AltTenantID,
				RepositoryNWO:        types.RepositoryFullName{Name: "launch", Owner: "github"},
				RepositoryID:         types.GlobalID("repo"),
				RepositoryDatabaseID: 1123,
				IsTrusted:            false,
				PlanOwnerID:          types.GlobalID("github-ent"),
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.desc, func(t *testing.T) {
			ctx := context.Background()
			clientFactory := &github.MockFactory{}
			client := &github.MockClient{}
			client.Mock.On("RepositoryInfoFromID", mock.Anything, tc.repoID).Return(tc.response, tc.err)
			clientFactory.Mock.On("NewClientForRepositoryOwner", mock.Anything, tc.repoID, tc.owner).Return(client, nil)

			db := &deployer.MockAzpResourcesRepository{}
			if tc.response != nil {
				db.Mock.On("TryGet", mock.Anything, tc.response.ID).Return(
					tc.azpResource, tc.azpGetErr,
				)
			}

			resolver := NewRepositoryMetadataResolver(clientFactory, db, tc.owner, log.NullLogger)

			meta, err := resolver.GetRepoMetadataFromGlobalID(ctx, tc.owner, tc.repoID)
			if tc.err != nil {
				require.True(t, errors.Is(err, tc.err))
			} else {
				require.NoError(t, err)
			}
			require.Equal(t, tc.metadata, meta)
		})
	}
}

func TestStubWorkflowSource_Clone(t *testing.T) {
	stubWorkflowSource := &workflowparser.StubWorkflowSource{
		CallerRepoID: "R_fake",
		CallerRepoNWO: types.RepositoryFullName{
			Owner: "github",
			Name:  "launch",
		},
		SourceMap: map[string]workflowparser.WorkflowDetails{
			"github/launch@.github/workflows/build.yml@main": {
				Content: "some yaml file content",
				RefType: "refs/heads/",
				Sha:     "shavalueabcd1234",
			}},
		CallerRepoRef: "main",
		CallerRepoSHA: "shavalueabcd1234",
	}

	description := "StubWorkflowSource Clone() performs deep clone"
	t.Run(description, func(t *testing.T) {
		cloned := stubWorkflowSource.Clone().(*workflowparser.StubWorkflowSource)
		if cloned == nil {
			t.Errorf("Clone() returned nil")
		}

		// check the values are copied
		require.Equal(t, stubWorkflowSource.CallerRepoID, cloned.CallerRepoID)
		require.Equal(t, stubWorkflowSource.CallerRepoNWO, cloned.CallerRepoNWO)
		require.Equal(t, stubWorkflowSource.SourceMap, cloned.SourceMap)
		require.Equal(t, stubWorkflowSource.CallerRepoRef, cloned.CallerRepoRef)
		require.Equal(t, stubWorkflowSource.CallerRepoSHA, cloned.CallerRepoSHA)

		// check they are referencing different addresses
		pCallerRepoID := fmt.Sprintf("%p", &stubWorkflowSource.CallerRepoID)
		pCallerRepoNWO := fmt.Sprintf("%p", &stubWorkflowSource.CallerRepoNWO)
		pSourceMap := fmt.Sprintf("%p", stubWorkflowSource.SourceMap)
		pCallerRepoRef := fmt.Sprintf("%p", &stubWorkflowSource.CallerRepoRef)
		pCallerRepoSHA := fmt.Sprintf("%p", &stubWorkflowSource.CallerRepoSHA)

		pClonedCallerRepoID := fmt.Sprintf("%p", &cloned.CallerRepoID)
		pClonedCallerRepoNWO := fmt.Sprintf("%p", &cloned.CallerRepoNWO)
		pClonedSourceMap := fmt.Sprintf("%p", cloned.SourceMap)
		pClonedCallerRepoRef := fmt.Sprintf("%p", &cloned.CallerRepoRef)
		pClonedCallerRepoSHA := fmt.Sprintf("%p", &cloned.CallerRepoSHA)

		require.NotEqual(t, pCallerRepoID, pClonedCallerRepoID)
		require.NotEqual(t, pCallerRepoNWO, pClonedCallerRepoNWO)
		require.NotEqual(t, pSourceMap, pClonedSourceMap)
		require.NotEqual(t, pCallerRepoRef, pClonedCallerRepoRef)
		require.NotEqual(t, pCallerRepoSHA, pClonedCallerRepoSHA)
	})
}

func TestWorkflowSourceFactory_InternalErrors(t *testing.T) {

	commonRepoResolver := newStubRepoMetadataResolver()
	commonRepoResolver.store(FakeOwnerId2, FakeRepoId2, "owner2", "repo2", FakeTenantID, true)

	tests := []struct {
		desc string

		setupAuthzClient func() authzd.Client
		spokesdClient    spokesd.Client
		repoResolver     RepositoryMetadataResolver

		environment        string
		callerRepo         *CallerRepo
		callerRepoMetadata *workflowparser.RepositoryMetadata
		wfRef              model.WorkflowRef
		expectedErr        error
		expectedMeta       *workflowparser.RepositoryMetadata
	}{
		{
			desc: "error when getting repo metadata from nwo",
			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{},
			repoResolver:  newStubRepoMetadataResolverFromError(errors.New("error getting repo metadata")),
			environment:   launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "wrongOwner",
					Name:  "wrongRepo",
				},
			},
			expectedErr: terrors.NewInternalError(errors.New("error while fetching repo metadata: error getting repo metadata")),
		},
		{
			desc: "error resolving repository ID from nwo in unknown app environments",
			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{},
			repoResolver:  newStubRepoMetadataResolverFromError(errors.New("error getting repo metadata")),
			environment:   "something else",
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "wrongOwner",
					Name:  "wrongRepo",
				},
			},
			expectedErr: terrors.NewInternalError(errors.New("error while fetching repo metadata: error getting repo metadata")),
		},
		{
			desc: "error when initial caller id is empty",
			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{},
			repoResolver:  commonRepoResolver,
			environment:   launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
				RepositoryID:         FakeRepoId2,
			},
			expectedErr: terrors.NewInternalError(errors.New("initial caller id should not be empty")),
		},
		{
			desc: "error when validating actor permission",
			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					err: errors.New("error authorizing"),
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{},
			repoResolver:  commonRepoResolver,
			environment:   launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				DatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
				RepositoryID:         FakeRepoId2,
			},
			expectedErr: terrors.NewInternalError(errors.New("validating actor permission: authorizing access permission: error authorizing")),
		},
		{
			desc: "error resolving SHA from ref",
			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"1:2": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				err: map[string]error{
					"ResolveObject": errors.New("error resolving object"),
				},
			},
			repoResolver: commonRepoResolver,
			environment:  launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				DatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring(""),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
				RepositoryID:         FakeRepoId2,
			},
			expectedErr: terrors.NewInternalError(errors.New("resolving ref to sha: error resolving object")),
		},
		{
			desc: "error getting workflow from ref",
			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"1:2": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/main": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				err: map[string]error{
					"GetBlobContents": errors.New("error getting blob contents"),
				},
			},
			repoResolver: commonRepoResolver,
			environment:  launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				DatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring("main"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
				RepositoryID:         FakeRepoId2,
			},
			expectedErr: terrors.NewInternalError(errors.New("getting blob contents: error getting blob contents")),
		},
		{
			desc: "error checking commit reachability",
			setupAuthzClient: func() authzd.Client {
				return authzd.NewTestClient(&stubAuthzd{
					byRepoID: map[string]bool{
						"1:2": true,
					},
				}, observability.NewTestObservability())
			},
			spokesdClient: &stubClient{
				byRef: map[string]string{
					"refs/heads/main": "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
				},
				err: map[string]error{
					"CheckCommitReachability": errors.New("error checking commit reachability"),
				},
			},
			repoResolver: commonRepoResolver,
			environment:  launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				DatabaseID: 1,
			},
			wfRef: model.WorkflowRef{
				Owner: "owner2",
				Repo:  "repo2",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			expectedMeta: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner2",
					Name:  "repo2",
				},
				RepositoryDatabaseID: 2,
				RepositoryID:         FakeRepoId2,
			},
			expectedErr: terrors.NewInternalError(errors.New("validating commit: checking commit reachability: error checking commit reachability")),
		},
		{
			desc: "error getting blob contents using commit SHA",
			setupAuthzClient: func() authzd.Client {
				return nil
			},
			spokesdClient: &stubClient{
				byRepoCommit: map[string][]string{
					"1:bd308308d5a52f33da3f8e837bb5febeeaa366bb": {"bd308308d5a52f33da3f8e837bb5febeeaa366bb"},
				},
				err: map[string]error{
					"GetBlobContents": errors.New("error getting blob contents"),
				},
			},
			repoResolver: newStubRepoMetadataResolver(),
			environment:  launchconfig.ProductionAppEnv.String(),
			callerRepo: &CallerRepo{
				RepoID: FakeRepoId1,
				NWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				DatabaseID: 1,
				Ref:        "bd308308d5a52f33da3f8e837bb5febeeaa366bb",
			},
			callerRepoMetadata: &workflowparser.RepositoryMetadata{
				RepositoryNWO: types.RepositoryFullName{
					Owner: "owner",
					Name:  "repo",
				},
				RepositoryDatabaseID: 1,
				RepositoryID:         FakeRepoId1,
			},
			wfRef: model.WorkflowRef{
				Owner: ".",
				Repo:  ".",
				Path:  ".github/workflows/workflow.yml",
				Version: model.VersionRef{
					GitRef: pstring("bd308308d5a52f33da3f8e837bb5febeeaa366bb"),
				},
			},
			expectedErr: terrors.NewInternalError(errors.New("getting blob contents: error getting blob contents")),
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()

			testutils.SetLaunchConfigEnv(t, testutils.EnvPair{
				Key:   "LAUNCH_ENV",
				Value: tt.environment,
			})

			twirpClient := &ghtwirp.MockClient{}
			twirpClient.On("IsFeatureEnabledForRepoOrOwners", mock.Anything, ghclient.ExcludeCalledWorkflowsFromRedirectedRepositoriesFlag, mock.Anything).Return(true)

			if tt.expectedMeta != nil {
				twirpClient.On("FindRepositoriesByName", mock.Anything, []string{tt.wfRef.GetNWO().String()}).
					Return(makeRepositoriesInfoFromMetadata(bucket(tt.expectedMeta)), nil)
			}
			factory := SpokesdWorkflowSourceFactory(tt.setupAuthzClient(), tt.spokesdClient, twirpClient, log.NullLogger, observability.NewTestObservability())

			invocationEvent := InvokingEvent{
				Name: flowevents.Push,
			}

			wfSrc := factory.Build(ctx, tt.repoResolver, tt.callerRepo, &invocationEvent, types.NilGlobalID, uuid.Nil)
			_, _, _, gotErr := wfSrc.GetWorkflowFile(ctx, tt.wfRef, tt.callerRepoMetadata, 0)

			require.Error(t, gotErr)
			require.True(t, terrors.IsInternalError(gotErr))
			require.EqualError(t, gotErr, tt.expectedErr.Error())
		})
	}
}

func (c *stubClient) ResolveObjectsByCommitShaAndPath(ctx context.Context, req *spokesd.ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return nil, nil
}

func (c *stubClient) ResolveObjectsByRef(ctx context.Context, req *spokesd.ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return nil, nil
}

// Workflow source won't need this. Hence making it a no-op test
func (c *stubClient) GetBlobContentsBatch(ctx context.Context, req *spokesd.GetBlobContentsBatchRequest) (*spokesd.GetBlobContentsBatchResponse, error) {
	return nil, nil
}

func pstring(s string) *string {
	return &s
}

func makeResolvedFile(path, text, ref, sha, nwo string) *types.ResolvedFile {
	h := sha1.New()
	_, _ = h.Write([]byte(text))
	return &types.ResolvedFile{
		Path:          path,
		Text:          text,
		Ref:           ref,
		SHA:           sha,
		RepositoryNwo: nwo,
	}
}

func softCompareRepositoryMetadata(t *testing.T, expected *workflowparser.RepositoryMetadata, actual *workflowparser.RepositoryMetadata) {
	if expected == nil {
		// The caller has no expectations.
		return
	}

	if actual == nil {
		t.Errorf("actual RepositoryMetadata was nil")
	}

	expectedFields := []string{"TenantID", "RepositoryNWO", "RepositoryID", "RepositoryDatabaseID", "PlanOwnerID", "IsTrusted"}
	fingerprintStruct(t, *expected, expectedFields)

	if expected.TenantID != "" {
		require.Equalf(t, expected.TenantID, actual.TenantID, "comparing RepositoryMetadata::TenantID")
	}
	if !expected.RepositoryNWO.IsBlank() {
		require.Equalf(t, expected.RepositoryNWO, actual.RepositoryNWO, "comparing RepositoryMetadata::RepositoryNWO")
	}
	if !expected.RepositoryID.IsZeroValue() {
		require.Equalf(t, expected.RepositoryID, actual.RepositoryID, "comparing RepositoryMetadata::RepositoryID")
	}
	if expected.RepositoryDatabaseID != 0 {
		require.Equalf(t, expected.RepositoryDatabaseID, actual.RepositoryDatabaseID, "comparing RepositoryMetadata::RepositoryDatabaseID")
	}
	if !expected.PlanOwnerID.IsZeroValue() {
		require.Equalf(t, expected.PlanOwnerID, actual.PlanOwnerID, "comparing RepositoryMetadata::PlanOwnerID")
	}
	require.Equalf(t, expected.IsTrusted, actual.IsTrusted, "comparing RepositoryMetadata::IsTrusted")
}

func fingerprintStruct[T any](t *testing.T, sample T, expectedFields []string) {
	reflectedType := reflect.TypeOf(sample)

	lengthMismatchMsg := "Test representation of %v is out-of-date, please update callers of fingerprintStruct to match."
	require.Equal(t, len(expectedFields), reflectedType.NumField(), lengthMismatchMsg, reflectedType)
	for _, fieldName := range expectedFields {
		_, found := reflectedType.FieldByName(fieldName)
		require.Truef(t, found, "Expected field, '%s', not found on type %v", fieldName, reflectedType)
	}
}

type stubRepoMetadataResolver struct {
	repos map[types.RepositoryFullName]workflowparser.RepositoryMetadata // keyed by NWO
	err   error
}

func newStubRepoMetadataResolver() *stubRepoMetadataResolver {
	return &stubRepoMetadataResolver{
		repos: make(map[types.RepositoryFullName]workflowparser.RepositoryMetadata),
		err:   nil,
	}
}

func newStubRepoMetadataResolverWithSeedData(t *testing.T, ownerID types.GlobalID, repoID types.GlobalID, ownerName string, repoName string, tenantID string, trusted bool) *stubRepoMetadataResolver {
	resolver := newStubRepoMetadataResolver()
	_, err := resolver.store(ownerID, repoID, ownerName, repoName, tenantID, trusted)
	if err != nil {
		t.Error(err)
		return nil
	}

	return resolver
}

func newStubRepoMetadataResolverFromError(cannedError error) *stubRepoMetadataResolver {
	resolver := newStubRepoMetadataResolver()
	resolver.err = cannedError
	return resolver
}

func (rir *stubRepoMetadataResolver) store(ownerID types.GlobalID, repoID types.GlobalID, ownerName string, repoName string, tenantID string, trusted bool) (*workflowparser.RepositoryMetadata, error) {

	_, repoDatabaseID, err := repoID.Decode()
	if err != nil {
		return nil, err
	}

	metdata := workflowparser.RepositoryMetadata{
		PlanOwnerID:          ownerID,
		RepositoryID:         repoID,
		RepositoryDatabaseID: uint64(repoDatabaseID),
		RepositoryNWO:        types.RepositoryFullName{Owner: ownerName, Name: repoName},
		TenantID:             tenantID,
		IsTrusted:            trusted,
	}

	normalizedNWO := types.RepositoryFullName{
		Owner: strings.ToLower(ownerName),
		Name:  strings.ToLower(repoName),
	}
	rir.repos[normalizedNWO] = metdata

	return &metdata, nil
}

func (rir *stubRepoMetadataResolver) GetRepoMetadataFromGlobalID(ctx context.Context, ownerID types.GlobalID, repoID types.GlobalID) (*workflowparser.RepositoryMetadata, error) {
	if rir.err != nil {
		return nil, rir.err
	}

	// In practice, there's never more than a few entries in a stubRepoMetadataResolver,
	// so just do a linear scan through the map values (rather than maintaining a secondary index).
	for _, v := range rir.repos {
		if repoID.IsEquivalent(v.RepositoryID) {
			if ownerID.IsZeroValue() || ownerID.IsEquivalent(v.PlanOwnerID) {
				return &v, nil
			}
		}
	}

	return nil, fmt.Errorf("repo not stubbed. (ownerID: '%v', repoID: '%v')", ownerID, repoID)
}

type stubClient struct {
	byRepoOIDPath map[string]string
	byRef         map[string]string
	byRepoCommit  map[string][]string
	err           map[string]error
}

func (c *stubClient) GetBlobContents(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	err := c.err["GetBlobContents"]
	if err != nil {
		return nil, err
	}
	switch reqt := req.Blob.(type) {
	case *blobs.GetBlobContentsRequest_ByRefPath:
		panic("should not be used")
	case *blobs.GetBlobContentsRequest_ByObjectIdPath:
		commit := reqt.ByObjectIdPath.Oid.Id
		path := reqt.ByObjectIdPath.Path.Name
		idxPath := fmt.Sprintf("%d:%s:%s", req.Repository.Id, commit, path)
		content, ok := c.byRepoOIDPath[idxPath]
		if !ok {
			return nil, twirp.NotFoundError(fmt.Sprintf("no value for %q", idxPath))
		}

		return &blobs.GetBlobContentsResponse{
			Contents:  []byte(content),
			Size:      uint64(len([]byte(content))),
			Truncated: false,
		}, nil
	default:
		panic("not implemented")
	}
}

func (c *stubClient) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	err := c.err["ResolveObject"]
	if err != nil {
		return nil, err
	}
	ref := string(req.ObjectName.Name)
	sha, ok := c.byRef[ref]
	if !ok {
		return nil, twirp.NotFoundError(fmt.Sprintf("no value for %q", ref))
	}
	return &objects.ResolveObjectResponse{
		Oid: &sTypes.ObjectID{Id: sha},
	}, nil
}

func (c *stubClient) CheckCommitReachability(ctx context.Context, req *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error) {
	err := c.err["CheckCommitReachability"]
	if err != nil {
		return nil, err
	}
	switch sel := req.Selector.(type) {
	case *commits.CheckCommitReachabilityRequest_ObjectIdSelector:
		if len(sel.ObjectIdSelector.Oids) != 1 {
			panic("exactly 1 commit expected in the request")
		}
		commit := sel.ObjectIdSelector.Oids[0].Id
		idxPath := fmt.Sprintf("%d:%s", req.Repository.Id, commit)
		reachableCommits, ok := c.byRepoCommit[idxPath]
		if !ok {
			return nil, twirp.NotFoundError(fmt.Sprintf("no value for %q", idxPath))
		}

		var ids []*sTypes.ObjectID
		for _, sha := range reachableCommits {
			ids = append(ids, &sTypes.ObjectID{Id: sha})
		}
		return &commits.CheckCommitReachabilityResponse{
			Commits: ids,
		}, nil
	default:
		panic("not implemented")
	}
}

type stubAuthzd struct {
	byRepoID map[string]bool
	err      error
}

func (autzs *stubAuthzd) Authorize(_ context.Context, req *authzpb.Request) (*authzpb.Decision, error) {
	if autzs.err != nil {
		return nil, autzs.err
	}

	var callerRepo, calledRepo, version int64
	var actionValue, actorType, subjectType string
	for _, attr := range req.Attributes {
		switch attrName := attr.GetId(); attrName {
		case authzd.AuthzdAction:
			actionValue = attr.Value.GetStringValue()
		case authzd.AuthzdActorType:
			actorType = attr.Value.GetStringValue()
		case authzd.AuthzdSubjectType:
			subjectType = attr.Value.GetStringValue()
		case authzd.AuthzdActorID:
			callerRepo = attr.Value.GetIntegerValue()
		case authzd.AuthzdSubjectRepositoryID:
			calledRepo = attr.Value.GetIntegerValue()
		case authzd.AuthzdVersion:
			version = attr.Value.GetIntegerValue()
		}
	}

	missingAttributes := []string{}
	if actionValue == "" || actionValue != authzd.UseCallableWorkflow {
		missingAttributes = append(missingAttributes, authzd.AuthzdAction)
	}
	if actorType == "" || actorType != authzd.Repository {
		missingAttributes = append(missingAttributes, authzd.AuthzdActorType)
	}
	if subjectType == "" || subjectType != authzd.Repository {
		missingAttributes = append(missingAttributes, authzd.AuthzdSubjectType)
	}
	if callerRepo == 0 {
		missingAttributes = append(missingAttributes, authzd.AuthzdActorID)
	}
	if calledRepo == 0 {
		missingAttributes = append(missingAttributes, authzd.AuthzdSubjectRepositoryID)
	}
	if len(missingAttributes) > 0 {
		return nil, errors.Errorf("Missing request attributes: %v", missingAttributes)
	}

	if version != 0 {
		return nil, errors.Errorf("Version attribute should not be used for latest authzd policy request used in GHES and Dotcom")
	}

	idx := fmt.Sprintf("%d:%d", callerRepo, calledRepo)
	permission, ok := autzs.byRepoID[idx]
	if !ok {
		panic(fmt.Sprintf("did not mock for the repo id: %v", idx))
	}

	if permission {
		return &authzpb.Decision{
			Result: authzpb.Result(authzpb.Result_ALLOW),
		}, nil
	}

	return &authzpb.Decision{
		Result: authzpb.Result(authzpb.Result_DENY),
	}, nil
}

func (autzs *stubAuthzd) BatchAuthorize(_ context.Context, _ *authzpb.BatchRequest) (*authzpb.BatchDecision, error) {
	panic("should not be used")
}

func makeRepositoriesInfo(repos []*CallerRepo) *ghtwirp.RepositoriesInfo {
	var results []*ghactions.Repository = nil
	for _, caller := range repos {
		if caller != nil {
			newMember := ghactions.Repository{
				GlobalRelayId: string(caller.RepoID),
				Id:            int64(caller.DatabaseID),
				Name:          caller.NWO.Name,
				OwnerLogin:    caller.NWO.Owner,
				Visibility:    ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
			}
			results = append(results, &newMember)
		}
	}
	return &ghtwirp.RepositoriesInfo{
		Repositories:                     results,
		RepositoriesNotFoundErrorMessage: "",
	}
}

func makeRepositoriesInfoFromMetadata(repos []*workflowparser.RepositoryMetadata) *ghtwirp.RepositoriesInfo {
	var results []*ghactions.Repository = nil
	for _, metadata := range repos {
		if metadata != nil {
			newMember := ghactions.Repository{
				GlobalRelayId: string(metadata.RepositoryID),
				Id:            int64(metadata.RepositoryDatabaseID),
				Name:          metadata.RepositoryNWO.Name,
				OwnerLogin:    metadata.RepositoryNWO.Owner,
				Visibility:    ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PUBLIC,
			}
			results = append(results, &newMember)
		}
	}
	return &ghtwirp.RepositoriesInfo{
		Repositories:                     results,
		RepositoriesNotFoundErrorMessage: "",
	}
}

func bucket[T any](member T) []T {
	return []T{member}
}
