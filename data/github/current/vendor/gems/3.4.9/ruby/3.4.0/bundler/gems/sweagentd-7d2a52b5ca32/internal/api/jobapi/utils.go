package jobapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	authd "github.com/github/authnd/client"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/auth"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/requestctx"
	gg "github.com/google/go-github/v75/github"
)

var (
	allowedAPICredentialTypes = []authd.CredentialType{
		authd.CredentialTypeOauthApplicationAccessToken,
		authd.CredentialTypeUserToServerToken,
		authd.CredentialTypeFineGrainedPersonalAccessToken,
		authd.CredentialTypeLegacyPersonalAccessToken,
	}
	requiredAccessActionsDefault    = []string{"pull", "push", "create_pull_request", "write_actions"}
	requiredAccessActionsPrivileged = []string{"pull"}
)

// BaseJobResponse values that are always present - though SessionID may be "" in development
type BaseJobResponse struct {
	ID          string          `json:"job_id"`
	SessionID   string          `json:"session_id"`
	Status      jobs.JobStatus  `json:"status"`
	Actor       *gg.User        `json:"actor"`
	CreatedAt   gg.Timestamp    `json:"created_at"`
	UpdatedAt   gg.Timestamp    `json:"updated_at"`
	PullRequest *gg.PullRequest `json:"pull_request,omitempty"`
}

// FullJobResponse is the base response + extended properties returned from GET / PUT endpoint, but not from create
type FullJobResponse struct {
	BaseJobResponse

	ProblemStatement  string                                 `json:"problem_statement,omitempty"`
	ContentFilterMode jobs.ProblemStatementContentFilterMode `json:"content_filter_mode,omitempty"`
	WorkflowRun       *gg.WorkflowRun                        `json:"workflow_run,omitempty"`
	Error             *jobs.JobError                         `json:"error,omitempty"`
	EventType         jobs.EventType                         `json:"event_type,omitempty"`
	EventURL          string                                 `json:"event_url,omitempty"`
	EventIdentifiers  []string                               `json:"event_identifiers,omitempty"`
	EventContent      string                                 `json:"event_content,omitempty"`
}

// Hydrates base job details for the passed in BaseJobResponse object
func (h *Handler) hydrateBaseJobResponse(ctx context.Context, gh github.ClientInterface, job *jobs.Job, baseJobResponse *BaseJobResponse, includeUserAndPullRequestObjects bool) error {
	var err error
	actor := &gg.User{
		ID:    &job.ActorID,
		Login: &job.ActorLogin,
	}
	if includeUserAndPullRequestObjects {
		actor, err = gh.GetUserById(ctx, uint64(job.ActorID))
		if err != nil {
			return fmt.Errorf("failed to get actor by ID: %d", job.ActorID)
		}
	}

	// Adapt to the two types of job details we support
	baseJobResponse.ID = job.ID
	baseJobResponse.SessionID = job.SessionID
	baseJobResponse.CreatedAt = gg.Timestamp{Time: time.Unix(job.CreatedAt, 0)}
	baseJobResponse.UpdatedAt = gg.Timestamp{Time: time.Unix(job.UpdatedAt, 0)}
	baseJobResponse.Status = job.Status
	baseJobResponse.Actor = actor

	// If a pull request is set on the job, fetch the PR details and add it
	if job.PullRequestID != 0 {
		baseJobResponse.PullRequest = &gg.PullRequest{
			ID:     &job.PullRequestID,
			Number: &job.PullRequestNumber,
		}
		if includeUserAndPullRequestObjects {
			// On error we'll just include the PR info already set
			pr, err := gh.GetPullRequest(ctx, job.RepoID, job.PullRequestNumber)
			if err == nil {
				baseJobResponse.PullRequest = pr
			}
		}
	}

	return nil
}

// Hydrates full job details for the passed in FullJobResponse object
func (h *Handler) hydrateFullJobResponse(ctx context.Context, gh github.ClientInterface, job *jobs.Job, fullJobResponse *FullJobResponse) error {
	if fullJobResponse == nil {
		return errors.New("fullJobResponse cannot be nil")
	}

	includeUserAndPullRequestObjects := false // we never include full PR details in this response
	err := h.hydrateBaseJobResponse(ctx, gh, job, &fullJobResponse.BaseJobResponse, includeUserAndPullRequestObjects)
	if err != nil {
		return fmt.Errorf("failed to hydrate base job response: %w", err)
	}

	fullJobResponse.ProblemStatement = job.ProblemStatement.Content
	fullJobResponse.ContentFilterMode = job.ProblemStatement.ContentFilterMode
	fullJobResponse.Error = job.Error
	fullJobResponse.EventType = job.EventType
	fullJobResponse.EventURL = job.EventURL
	fullJobResponse.EventIdentifiers = job.EventIdentifiers
	fullJobResponse.EventContent = job.EventContent
	if job.ComputeID != "" {
		runID, err := strconv.ParseInt(job.ComputeID, 10, 64)
		if err != nil {
			return fmt.Errorf("invalid compute ID: %s", job.ComputeID)
		}
		fullJobResponse.WorkflowRun = &gg.WorkflowRun{
			ID: &runID,
		}
	}

	return nil
}

func (h *Handler) errorResponse(w http.ResponseWriter, message string, code int) error {
	errResponse := gg.ErrorResponse{
		Message: message,
	}

	jsonData, err := json.Marshal(errResponse)
	if err != nil {
		return err
	}
	http.Error(w, string(jsonData), code)
	return nil
}

func (h *Handler) verifyTokenAccess(ctx context.Context, user *requestctx.UserInfo, repoOwner, repoName string, requiredAccessActions []string) (bool, error) {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	tokenHash := auth.HashToken(user.TokenInfo.Token)

	if user.TokenInfo.Type == string(authd.CredentialTypeUserToServerToken) {
		hasCapability, err := h.privilegedAppChecker.IsCapable(ctx, user.TokenInfo.ApplicationID, user.TokenInfo.ApplicationType)
		if err != nil {
			return false, fmt.Errorf("API failed to check app capabilities: %w", err)
		}
		if hasCapability {
			logger.Info("Token is from privileged App")
			requiredAccessActions = requiredAccessActionsPrivileged
		} else {
			logger.Info("Token is NOT from privileged App")
		}
	}

	logger.WithFields(
		kvp.String("repo_owner", repoOwner),
		kvp.String("repo_name", repoName),
		kvp.String("token_hash", tokenHash),
		kvp.String("required_access_actions", strings.Join(requiredAccessActions, ",")),
	).Info("verifying token access for required actions")

	rules := make([]*githubtwirp.HasAccessCheck, len(requiredAccessActions))
	nwo := fmt.Sprintf("%s/%s", repoOwner, repoName)
	for i, action := range requiredAccessActions {
		rules[i] = &githubtwirp.HasAccessCheck{
			Action:        action,
			ResourceType:  "Repository",
			RepositoryNWO: nwo,
		}
	}
	hasAccess, err := githubtwirp.TokenHasAccess(ctx, h.ghTwirp, user, rules)
	if err != nil {
		logger.WithError(err).Error("error checking token access")
		return false, err
	}
	logger.WithFields(
		kvp.Bool("has_access", hasAccess),
		kvp.String("token_hash", tokenHash),
		kvp.String("required_access_actions", strings.Join(requiredAccessActions, ",")),
	).Info("checking token access")
	return hasAccess, nil
}

// truncate truncates a string to the given number of UTF-8 characters, appending "..." to the end.
// If the provided length is less than or equal to 0 an empty string is returned.
// If the string is already shorter than the given length, the string is returned as-is.
func truncate(s string, n int) string {
	if n <= 0 {
		return ""
	}

	runeCount := utf8.RuneCountInString(s)
	if runeCount > n {
		runes := []rune(s)
		if n <= 3 {
			return string(runes[:n])
		}
		return string(runes[:n-3]) + "..."
	}
	return s
}

// truncateAgentDescriptionWithLink truncates an agent description to fit within the given maximum length
// while accounting for a suffix that links to the agent's configuration. If truncation is needed,
// it appends "... [see config here](https://github.com/<org>/<repo>/blob/main/.github/agents/<agent_name>)"
// and ensures the final result doesn't exceed maxLength.
func truncateAgentDescriptionWithLink(description, repoOwner, repoName, agentName string, maxLength int) string {
	runeCount := utf8.RuneCountInString(description)
	if runeCount <= maxLength {
		return description
	}

	// Build the suffix that will be appended if truncation occurs (TODO: support proxima link & versioning)
	configLink := fmt.Sprintf("https://github.com/%s/%s/blob/main/.github/agents/%s.md", repoOwner, repoName, agentName)
	suffix := fmt.Sprintf("... [see config here](%s)", configLink)
	suffixLength := utf8.RuneCountInString(suffix)

	// If the suffix itself is longer than maxLength, we can't fit anything meaningful
	if suffixLength >= maxLength {
		// Fall back to basic truncation without the link
		return truncate(description, maxLength)
	}

	// Calculate how much space we have for the actual description
	availableLength := maxLength - suffixLength

	// Truncate the description and append the suffix
	runes := []rune(description)
	return string(runes[:availableLength]) + suffix
}

// capLength caps a string to the given number of UTF-8 characters without appending "..." to the end.
// If the provided length is less than or equal to 0 an empty string is returned.
// If the string is already shorter than or equal to the given length, the string
// is returned as-is.
func capLength(s string, n int) string {
	if n <= 0 {
		return ""
	}
	runeCount := utf8.RuneCountInString(s)
	if runeCount <= n {
		return s
	}
	runes := []rune(s)
	return string(runes[:n])
}
