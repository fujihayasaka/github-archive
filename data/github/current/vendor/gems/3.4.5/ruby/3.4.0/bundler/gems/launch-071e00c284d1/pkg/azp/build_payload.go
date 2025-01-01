package azp

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/textproto"
	"time"

	errs "github.com/pkg/errors"

	parser "github.com/github/actions-workflow-parser/go"

	"github.com/github/launch/types"
)

// MultipartPayload represents a multi-part payload and its boundary.
type MultipartPayload struct {
	Boundary string
	Content  *bytes.Buffer
}

// BuildPayload represents the full multi-part build queue payload.
type BuildPayload struct {
	Root  RootPayload
	Files []FilePayload
}

// FilePayload represents a workflow file or other file referenced in a workflow file.
type FilePayload struct {
	Path    string
	Content []byte
}

// RootPayload is a struct representing the root part of the multi-part build
// queue payload.
//
// See: https://github.com/github/dreamlifter/blob/master/docs/adrs/0515-finalize-enqueue-endpoint-payload.md#decision
type RootPayload struct {
	PlanID           string                     `json:"planId"`
	Configuration    rootPayloadConfig          `json:"configuration"`
	Context          rootPayloadContext         `json:"context"`
	Secrets          map[string]string          `json:"secrets"`
	Variables        map[string]string          `json:"variables"`
	RerunContext     *rerunContext              `json:"rerunContext,omitempty"`
	WorkflowTemplate *parser.WorkflowTemplate   `json:"workflowTemplate,omitempty"`
	Concurrency      *parser.ConcurrencySetting `json:"concurrency,omitempty"`
}

type rerunContext struct {
	PreviousPlanID string   `json:"previousPlanId"`
	JobIDs         []string `json:"jobIds"`
}

// rootPayloadConfig contains the workflow file path used for this run and
// callback URLs to be used for status updates.
type rootPayloadConfig struct {
	MainFilePath    string                               `json:"mainFilePath"`
	Callbacks       rootPayloadCallbacks                 `json:"callbacks"`
	ReferencedFiles map[string]rootPayloadReferencedFile `json:"referencedFiles"`
	OidcConfig      oidcConfig                           `json:"oidcConfig"`
	RootWorkflow    rootWorkflow                         `json:"mainWorkflow"`
	IsLab           bool                                 `json:"isLab"`
}

// OIDCConfig contains the id-token claim customization related settings
type oidcConfig struct {
	SubClaimCustomizationTemplate string `json:"subClaimCustomizationTemplate"`
	CustomizeEnterpriseIssuer     bool   `json:"customizeEnterpriseIssuer"`
}

// rootPayloadCallbacks specifies URLs used for job and run status callbacks.
type rootPayloadCallbacks struct {
	JobStatusURL        string `json:"jobStatusUrl"`
	RunStatusURL        string `json:"runStatusUrl"`
	GateStatusURL       string `json:"gateStatusUrl"`
	EnvironmentURL      string `json:"environmentUrl"`
	PreJobURL           string `json:"preJobUrl"`
	TokenRefreshURL     string `json:"tokenRefreshUrl"`
	TokenRevokeURL      string `json:"tokenRevokeUrl"`
	ActionResolutionURL string `json:"actionResolutionUrl"`
	ReceiverURL         string `json:"receiverUrl"`
	SignatureKey        string `json:"signatureKey"`
	ResultsReceiverURL  string `json:"resultsReceiverURL"`
}

// rootPayloadReferencedFile describes a referenced workflow file
type rootPayloadReferencedFile struct {
	TenantID             string         `json:"tenantId"`
	Ref                  string         `json:"ref"`
	SHA                  string         `json:"sha"`
	Repository           string         `json:"repository"`
	IsTrusted            bool           `json:"isTrusted"`
	PlanOwnerID          types.GlobalID `json:"planOwnerId"`
	RepositoryID         types.GlobalID `json:"repositoryId"`
	RepositoryDatabaseID uint64         `json:"repositoryDatabaseId"`
}

// rootWorkflow describes the root workflow file. For reusable workflows,
// this describes calling workflow. For required workflow this describes
// workflow that resides in required workflow source repository.
type rootWorkflow struct {
	FilePath           string         `json:"filePath"`
	Ref                string         `json:"ref"`
	SHA                string         `json:"sha"`
	Repository         string         `json:"repository"`
	RepositoryID       types.GlobalID `json:"repositoryId"`
	IsRequiredWorkflow bool           `json:"isRequiredWorkflow"`
}

// rootPayloadContext specifies the context of the run, such as the commit SHA
// that was the head of the branch in question when the workflow was triggered.
type rootPayloadContext struct {
	Repository                        string                           `json:"repository"`
	RepositoryID                      types.GlobalID                   `json:"repositoryId"`
	RepositoryDatabaseID              int64                            `json:"repositoryDatabaseId"`
	RepositoryName                    string                           `json:"repositoryName"`
	RepositoryOwner                   string                           `json:"repositoryOwner"`
	RepositoryURL                     string                           `json:"repositoryUrl"`
	PrivateRepository                 bool                             `json:"privateRepository"`
	ForkedRepository                  bool                             `json:"forkedRepository"`
	RepositoryVisibility              string                           `json:"repositoryVisibility"`
	RepoSelfHostedRunnersDisabled     bool                             `json:"repoSelfHostedRunnersDisabled"`
	Actor                             string                           `json:"actor"`
	ActorID                           types.GlobalID                   `json:"actorId"`
	ActorDatabaseID                   int64                            `json:"actorDatabaseId"`
	ForkedPullRequest                 bool                             `json:"forkedPullRequest"`
	ForkedPullRequestEventContext     forkPullRequestEventContext      `json:"forkedPullRequestEventContext"`
	ParentRepositoryOwner             string                           `json:"parentRepositoryOwner,omitempty"`
	ParentRepositoryName              string                           `json:"parentRepositoryName,omitempty"`
	OwnerID                           string                           `json:"ownerID,omitempty"`
	OwnerDatabaseID                   int64                            `json:"ownerDatabaseID,omitempty"`
	OwnerCreatedAt                    time.Time                        `json:"ownerCreatedAt"`
	EnterpriseManagedBusinessID       types.GlobalID                   `json:"enterpriseManagedBusinessId,omitempty"`
	RunID                             int64                            `json:"runId"`
	RunNumber                         int64                            `json:"runNumber"`
	RunAttempt                        int64                            `json:"runAttempt"`
	Sha                               string                           `json:"sha"`
	Ref                               string                           `json:"ref"`
	RetentionDays                     int64                            `json:"retentionDays"`
	ActionsCacheSizeLimit             uint64                           `json:"artifactCacheSizeLimit"`
	RepositoryTier                    int64                            `json:"repositoryTier"`
	OidcSubClaimCustomizationTemplate string                           `json:"oidcSubClaimCustomizationTemplate"`
	WorkflowPermissionsPolicy         ActionsWorkflowPermissionsPolicy `json:"workflowPermissionsPolicy,omitempty"`
	GitHubEventInfo                   *gitHubEventInfo                 `json:"gitHubEventInfo,omitempty"`
	BillingPlanOwner                  rootPayloadBillingPlanOwner      `json:"billingPlanOwner"`
	ExtendedContext                   rootPayloadExtendedContext       `json:"extendedContext"`
	RunFeatureFlagsContext            map[string]bool                  `json:"runFeatureFlagsContext"`
	GitHubTenantSlug                  string                           `json:"gitHubTenantSlug,omitempty"`
}

type gitHubEventInfo struct {
	AbuseInfo     *types.ActionsAbuseTriggerInfo `json:"abuseInfo"`
	IsScheduled   bool                           `json:"isScheduled"`
	CustomerLabel string                         `json:"customerLabel"`
}

// rootPayloadBillingPlanOwner is used to share information about which account pays for this repository.
// This info is used for things like managing concurrency (plan) and monitoring for abuse.
//
// https://github.com/github/pe-actions/blob/master/docs/adrs/1115-billing-plan-owner-in-build-payload.md
type rootPayloadBillingPlanOwner struct {
	ID                     string `json:"id"`
	PlanSku                string `json:"planSku"`
	Type                   string `json:"type"`
	Name                   string `json:"name"`
	TenantID               string `json:"tenantId"`
	TenantName             string `json:"tenantName"`
	DatabaseID             int64  `json:"databaseId,omitempty"`
	OrganizationID         string `json:"organizationId,omitempty"`
	OrganizationTenantID   string `json:"organizationTenantId,omitempty"`
	OrganizationTenantName string `json:"organizationTenantName,omitempty"`
}

// rootPayloadExtendedContext is context not required by AZP that still affects
// the Actions runtime environment. It is deserialized as a dictionary (map) by
// Actions Service. The runner will set `GITHUB_#{uppercase(extendedContextKey)}`
// environment variables for every top-level key in its allowlist.
//
// Many of these come from https://developer.github.com/actions/creating-github-actions/accessing-the-runtime-environment/#environment-variables
//
// These are used in the workflow variable context, and so keys should be
// snake_cased.
type rootPayloadExtendedContext struct {
	Actor           string         `json:"actor"`
	TriggeringActor string         `json:"triggering_actor,omitempty"`
	Workflow        string         `json:"workflow"`
	HeadRef         string         `json:"head_ref"`
	BaseRef         string         `json:"base_ref"`
	EventName       string         `json:"event_name"`
	Event           map[string]any `json:"event"`
	ServerURL       string         `json:"server_url"`
	APIURL          string         `json:"api_url"`
	GraphQLURL      string         `json:"graphql_url"`
	RefName         string         `json:"ref_name"`
	RefProtected    bool           `json:"ref_protected"`
	RefType         string         `json:"ref_type"`
	SecretSource    string         `json:"secret_source"`
}

// forkPullRequestEventContext is additional context for pull requests from forks
// This information is sent through to Compute to help monitor
type forkPullRequestEventContext struct {
	HeadRepository        string         `json:"headRepository,omitempty"`
	HeadRepositoryID      types.GlobalID `json:"headRepositoryId,omitempty"`
	HeadRepositoryName    string         `json:"headRepositoryName,omitempty"`
	HeadRepositoryOwner   string         `json:"headRepositoryOwner,omitempty"`
	HeadRepositoryOwnerID types.GlobalID `json:"headRepositoryOwnerId,omitempty"`
}

// multipartPayloadOpt is called on a multipart writer to apply options to it
type multipartPayloadOpt = func(mw *multipart.Writer)

// ToMultipartPayload returns a multipart HTTP request payload from the BuildPayload.
//
// This accepts a list of functions that receive `func (mw multipart.Writer)`
// that are called on the writer before any parts are added.
func (b *BuildPayload) ToMultipartPayload(opts ...multipartPayloadOpt) (*MultipartPayload, error) {
	body := new(bytes.Buffer)
	mw := multipart.NewWriter(body)
	defer mw.Close()

	for _, opt := range opts {
		opt(mw)
	}

	// Write the root part to the payload
	rp, err := mw.CreatePart(textproto.MIMEHeader{
		"Content-Id":   []string{"root"},
		"Content-Type": []string{"application/json"},
	})
	if err != nil {
		return nil, errs.Wrap(err, "error creating multi-part payload root part")
	}
	rootPayload, err := json.Marshal(b.Root)
	if err != nil {
		return nil, errs.Wrap(err, "unable to marshal root payload")
	}
	if _, err := rp.Write(rootPayload); err != nil {
		return nil, errs.Wrap(err, "unable to write multi-part payload root part")
	}

	// Append each file part
	for _, filePayload := range b.Files {
		fp, err := mw.CreatePart(textproto.MIMEHeader{
			"Content-Id":          []string{filePayload.Path},
			"Content-Description": []string{"file"},
			"Content-Type":        []string{"text/plain"},
		})
		if err != nil {
			return nil, errs.Wrap(err, "error creating multi-part payload file part")
		}
		if _, err := fp.Write(filePayload.Content); err != nil {
			return nil, errs.Wrap(err, "unable to write multi-part payload file part")
		}
	}

	return &MultipartPayload{
		Boundary: mw.Boundary(),
		Content:  body,
	}, nil
}

// ContentType generate a Content-type value for this payload.
// See https://golang.org/src/mime/multipart/writer.go?s=1728:1773#L64
func (m *MultipartPayload) ContentType() string {
	return `multipart/related; boundary=` + m.Boundary + `; start=root; type="application/json"`
}
