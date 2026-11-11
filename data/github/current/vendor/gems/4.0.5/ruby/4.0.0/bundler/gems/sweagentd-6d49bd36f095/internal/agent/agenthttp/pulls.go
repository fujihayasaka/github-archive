package agenthttp

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/github/sweagentd/internal/featureflags"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/jobservice"

	chi "github.com/go-chi/chi/v5"
	"github.com/twitchtv/twirp"
)

// createPullRequest creates a pull request for a job via the Twirp CreatePullRequest API.
//
// Error responses:
//   - 400 Bad Request: missing job ID, missing title, invalid request body, or twirp.InvalidArgument
//   - 401 Unauthorized: authorization failed or invalid/missing nonce
//   - 403 Forbidden: twirp.PermissionDenied or twirp.Unauthenticated
//   - 404 Not Found: job not found or twirp.NotFound
//   - 409 Conflict: pull request already exists (ErrPullRequestExists or twirp.AlreadyExists)
//   - 500 Internal Server Error: assignment lookup failure or unrecognized errors
func (h *Handler) createPullRequest(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.createPullRequest")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.Logger.Named("agenthttp.Handler.createPullRequest")

	_, err := h.authorize(ctx)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("authorization failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	jobID := chi.URLParam(r, "jobID")
	if jobID == "" {
		logger.WithContext(ctx).Info("job ID not provided")
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
		logger.WithContext(ctx).WithError(err).Error("access validation failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)

		return
	}

	if job.IsTerminal() {
		logger.WithContext(ctx).Info("job is in terminal state, refusing to create PR")
		http.Error(w, "job is not running", http.StatusForbidden)

		return
	}

	var reqBody createPullRequestRequestDTO
	err = json.NewDecoder(r.Body).Decode(&reqBody)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to decode request body")
		http.Error(w, "invalid request body", http.StatusBadRequest)

		return
	}

	if reqBody.Title == "" {
		logger.WithContext(ctx).Info("missing required field: title")
		http.Error(w, "title is required", http.StatusBadRequest)

		return
	}

	assignment, err := h.store.GetAssignment(ctx, job.OwnerID, job.RepoID, job.AssignmentID)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to get assignment")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	if assignment.PullRequestID != 0 {
		logger.WithContext(ctx).Info("pull request already exists for assignment")
		writePullRequestConflictResponse(w, assignment.PullRequestID, assignment.PullRequestNumber)

		return
	}

	err = h.jobService.OpenPullRequest(ctx, h.twirp.SweagentdAPI(), assignment, job, reqBody.Title, reqBody.Description)
	if err != nil {
		if errors.Is(err, jobservice.ErrPullRequestExists) {
			logger.WithContext(ctx).WithError(err).Info("pull request already exists")
			http.Error(w, "pull request already exists", http.StatusConflict)

			return
		}

		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			switch twirpErr.Code() {
			case twirp.InvalidArgument:
				logger.WithContext(ctx).WithError(err).Info("invalid argument creating pull request")
				http.Error(w, twirpErr.Msg(), http.StatusBadRequest)

				return
			case twirp.NotFound:
				logger.WithContext(ctx).WithError(err).Info("resource not found creating pull request")
				http.Error(w, twirpErr.Msg(), http.StatusNotFound)

				return
			case twirp.PermissionDenied, twirp.Unauthenticated:
				logger.WithContext(ctx).WithError(err).Error("permission denied creating pull request")
				http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)

				return
			case twirp.AlreadyExists:
				logger.WithContext(ctx).WithError(err).Info("pull request already exists")
				http.Error(w, "pull request already exists", http.StatusConflict)

				return
			}
		}

		logger.WithContext(ctx).WithError(err).Error("failed to create pull request")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	// Persist the PR linkage to the store so subsequent requests see it.
	// When the feature flag is enabled, replace the full-document ETag check with a
	// targeted condition that only verifies pull_request_id hasn't changed. This
	// protects against concurrent PR linkage writes while allowing unrelated field
	// updates to proceed without causing 412 Precondition Failed errors.
	//
	// The condition accepts both 0 (not yet set) and the PR ID we just created.
	// This handles the race where copilot-mission-control's hydro consumer
	// processes the PullRequest create event and calls UpdateAssignment before
	// we persist the linkage here — both paths write the same PR ID.
	var jobPatchOpts []db.PatchJobOption
	var assignmentPatchOpts []db.PatchAssignmentOption
	if h.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentAgenticAppDisableEtagOnPRLinkage, job) {
		prCondition := db.FieldCondition{Path: "pull_request_id", Values: []any{int64(0), job.PullRequestID}}
		jobPatchOpts = append(jobPatchOpts, db.WithJobFieldConditions(prCondition))
		assignmentPatchOpts = append(assignmentPatchOpts, db.WithAssignmentFieldConditions(prCondition))
	}

	err = h.store.PatchJob(ctx, job, db.JobPatch{
		PullRequestID:     &job.PullRequestID,
		PullRequestNumber: &job.PullRequestNumber,
	}, jobPatchOpts...)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to persist job pull request fields")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	err = h.store.PatchAssignment(ctx, assignment, db.AssignmentPatch{
		PullRequestID:     &assignment.PullRequestID,
		PullRequestNumber: &assignment.PullRequestNumber,
	}, assignmentPatchOpts...)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to persist assignment pull request fields")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	resp := createPullRequestResponseDTO{
		ID:           job.PullRequestID,
		GithubNumber: job.PullRequestNumber,
	}

	respBytes, err := json.Marshal(resp)
	if err != nil {
		logger.WithContext(ctx).WithError(err).Error("failed to encode pull request response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)

		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_, _ = w.Write(respBytes)
}

func writePullRequestConflictResponse(w http.ResponseWriter, prID int64, prNumber int) {
	resp := createPullRequestResponseDTO{
		ID:           prID,
		GithubNumber: prNumber,
	}
	respBytes, err := json.Marshal(resp)
	if err != nil {
		http.Error(w, "pull request already exists", http.StatusConflict)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusConflict)
	_, _ = w.Write(respBytes)
}
