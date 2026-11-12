package agenthttp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"time"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/github/tokens"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"

	chi "github.com/go-chi/chi/v5"
)

var attachmentGUIDRegex = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

var errInvalidAttachmentGUID = goerrors.New("invalid attachment GUID format")

// downloadAttachment resolves a user-attachment GUID to a signed CDN URL.
// The runtime calls this endpoint instead of hitting the internal GitHub
// user-attachments API directly from external IPs (see #11694).
//
// Error responses:
//   - 400 Bad Request: missing job ID or invalid GUID
//   - 401 Unauthorized: authorization failed or invalid/missing nonce
//   - 404 Not Found: job not found
//   - 502 Bad Gateway: upstream GitHub API error
func (h *Handler) downloadAttachment(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.downloadAttachment")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)

	_, err := h.authorize(ctx)
	if err != nil {
		logger.WithError(err).Error("authorization failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	jobID := chi.URLParam(r, "jobID")
	if jobID == "" {
		logger.Info("job ID not provided")
		http.Error(w, "job_id is required", http.StatusBadRequest)
		return
	}

	job, err := h.svc.GetJob(ctx, jobID)
	if err != nil {
		h.handleDomainError(w, err)
		return
	}

	err = h.validateNonce(r, job.NonceHash)
	if err != nil {
		logger.WithError(err).Error("access validation failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	signedURL, err := h.resolveAttachmentURL(ctx, job, chi.URLParam(r, "guid"))
	if err != nil {
		if errors.Is(err, errInvalidAttachmentGUID) {
			http.Error(w, "invalid attachment GUID", http.StatusBadRequest)
			return
		}
		if errors.Is(err, agenticapp.ErrAgentNotFound) {
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
			return
		}
		logger.WithError(err).Error("failed to resolve attachment URL")
		http.Error(w, "failed to resolve attachment", http.StatusBadGateway)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	err = json.NewEncoder(w).Encode(downloadAttachmentResponseDTO{URL: signedURL})
	if err != nil {
		logger.WithError(err).Error("failed to encode response")
	}
}

// resolveAttachmentURL resolves a user-attachment GUID to a signed CDN URL by
// calling the internal GitHub user-attachments API on behalf of the agent.
func (h *Handler) resolveAttachmentURL(ctx context.Context, job *jobs.Job, guid string) (string, error) {
	if !attachmentGUIDRegex.MatchString(guid) {
		return "", errInvalidAttachmentGUID
	}

	if h.githubDownloadsURL == "" {
		return "", goerrors.New("github downloads URL is not configured")
	}

	app, err := h.appProvider.FindByID(ctx, job.AgentID)
	if err != nil {
		return "", goerrors.Errorf("failed to find app for attachment download: %w", err)
	}

	token, err := h.attachmentToken(ctx, app, job)
	if err != nil {
		return "", goerrors.Errorf("failed to get token for attachment download: %w", err)
	}

	downloadURL := fmt.Sprintf("%s/%s", h.githubDownloadsURL, guid)

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, downloadURL, http.NoBody)
	if err != nil {
		return "", goerrors.Errorf("failed to create attachment download request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	client := &http.Client{
		Timeout:   30 * time.Second,
		Transport: observability.NewTelemetryRoundTripper(http.DefaultTransport, h.obsv, "attachment-download", nil),
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", goerrors.Errorf("failed to fetch attachment URL: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return "", goerrors.Errorf("fetching attachment URL failed with status %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		URL string `json:"url"`
	}
	err = json.NewDecoder(io.LimitReader(resp.Body, 10*1024)).Decode(&result)
	if err != nil {
		return "", goerrors.Errorf("failed to decode attachment response: %w", err)
	}

	if result.URL == "" {
		return "", goerrors.New("no signed URL found in attachment response")
	}

	return result.URL, nil
}

// attachmentToken returns a token suitable for calling the internal user-attachments API on behalf of the job.
// User-billed jobs require a user-to-server token to determine the actor's visibility into the asset.
// Org-billed jobs fall back to a server-to-server token via GetTokenForJob.
func (h *Handler) attachmentToken(ctx context.Context, app sweagentd.AgenticApp, job *jobs.Job) (string, error) {
	api := h.twirp.SweagentdAPI()
	if job.IsBillToOrg() {
		target := sweagentd.ClientTargetForInstallationByOwnerID(app.AppID(), job.GetOwnerID())
		return tokens.GetTokenForJob(ctx, target, app.AppID(), api, api, app, job, &tokens.NoopCache{})
	}
	target := sweagentd.ClientTargetForUser(app.AppID(), job.GetActorID())
	return tokens.GetUserToServerToken(ctx, target, app.AppID(), api, job)
}
