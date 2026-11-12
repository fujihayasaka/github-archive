package agenthttp

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/agent"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	chi "github.com/go-chi/chi/v5"
	"github.com/twitchtv/twirp"
)

// signCommitRequest represents the request body for signing a commit.
type signCommitRequest struct {
	Author            string `json:"author"` // sent by gh-gpgsign; not used server-side
	Message           string `json:"message"`
	VerificationToken string `json:"verification_token"`
}

// signCommitResponse represents the response body for a signed commit.
type signCommitResponse struct {
	Signature string `json:"signature"`
}

// signCommit signs a commit on behalf of the agent by proxying to the GitHub signing Twirp API.
//
// Error responses:
//   - 400 Bad Request: missing job ID, missing payload, missing verification token, invalid request body, or co-author validation failure
//   - 401 Unauthorized: authorization failed or invalid verification token
//   - 404 Not Found: job not found
//   - 409 Conflict: job is in a terminal state
//   - 502 Bad Gateway: upstream signing Twirp API call failed
func (h *Handler) signCommit(w http.ResponseWriter, r *http.Request) {
	ctx, span := h.obsv.Tracer.Start(r.Context(), "agenthttp.Handler.signCommit")
	defer span.End()
	r = r.WithContext(ctx)
	logger := h.obsv.LoggerWithRequestTelemetry(ctx, r)
	baseTags := h.obsv.TelemetryTags(ctx).Merge(stats.Tags{
		"endpoint":               "sign_commit",
		"require_signed_commits": "unknown",
	})

	_, err := h.authorize(ctx)
	if err != nil {
		logger.WithError(err).Error("authorization failed")
		h.recordError(ctx, baseTags, "authorization_failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	jobID := chi.URLParam(r, "jobID")
	if jobID == "" {
		logger.Info("job ID not provided")
		h.recordError(ctx, baseTags, "missing_job_id")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	var reqBody signCommitRequest
	err = json.NewDecoder(r.Body).Decode(&reqBody)
	if err != nil {
		logger.WithError(err).Error("failed to decode request body")
		h.recordError(ctx, baseTags, "invalid_request_body")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	if reqBody.Message == "" {
		logger.Info("missing required field: message")
		h.recordError(ctx, baseTags, "missing_message")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	if reqBody.VerificationToken == "" {
		logger.Info("missing required field: verification_token")
		h.recordError(ctx, baseTags, "missing_verification_token")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	job, err := h.svc.GetJob(ctx, jobID)
	if err != nil {
		logger.WithError(err).Error("failed to get job")
		h.recordError(ctx, baseTags, "get_job_failed")
		switch {
		case errors.Is(err, agent.ErrInvalidJobIDFormat),
			errors.Is(err, agent.ErrInvalidJobIDOwner),
			errors.Is(err, agent.ErrInvalidJobIDRepo):
			http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		case errors.Is(err, agent.ErrJobNotFound):
			http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
		default:
			http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		}
		return
	}

	// Enrich tags with the job's commit signing requirement from the job record.
	baseTags = baseTags.Merge(stats.Tags{
		"require_signed_commits": strconv.FormatBool(job.RequireSignedCommits),
	})

	coAuthors, err := parseCoAuthorTrailers(reqBody.Message)
	if err != nil {
		logger.WithError(err).Info("co-author validation failed")
		h.recordError(ctx, baseTags, "invalid_co_author")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	if len(coAuthors) > 1 {
		emails := make([]string, len(coAuthors))
		for i, ca := range coAuthors {
			emails[i] = ca.email
		}
		logger.Info("multiple co-author trailers detected", kvp.Int("co_author_count", len(coAuthors)), kvp.Strings("co_author_emails", emails))
	}

	err = validateSingleCoAuthor(coAuthors)
	if err != nil {
		logger.WithError(err).Info("co-author validation failed")
		h.recordError(ctx, baseTags, "invalid_co_author")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	if subtle.ConstantTimeCompare([]byte(jobs.HashNonce(reqBody.VerificationToken)), []byte(job.NonceHash)) != 1 {
		logger.Info("access validation failed: invalid verification token")
		h.recordError(ctx, baseTags, "access_validation_failed")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	if job.IsTerminal() {
		logger.Info("job is in a terminal state")
		h.recordError(ctx, baseTags, "job_terminal")
		http.Error(w, http.StatusText(http.StatusConflict), http.StatusConflict)
		return
	}

	err = validateCoAuthorMatchesInitiator(coAuthors, job)
	if err != nil {
		logger.WithError(err).Info("co-author validation failed")
		h.recordError(ctx, baseTags, "invalid_co_author")
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	signature, err := h.svc.SignCommit(ctx, job, reqBody.Message)
	if err != nil {
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) {
			switch twirpErr.Code() {
			case twirp.InvalidArgument:
				logger.WithError(err).Info("invalid argument signing commit")
				h.recordError(ctx, baseTags, "upstream_invalid_argument")
				http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
				return
			case twirp.NotFound:
				logger.WithError(err).Info("resource not found signing commit")
				h.recordError(ctx, baseTags, "upstream_not_found")
				http.Error(w, http.StatusText(http.StatusNotFound), http.StatusNotFound)
				return
			case twirp.PermissionDenied, twirp.Unauthenticated:
				logger.WithError(err).Error("permission denied signing commit")
				h.recordError(ctx, baseTags, "upstream_permission_denied")
				http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
				return
			}
		}

		logger.WithError(err).Error("failed to sign commit via upstream API")
		h.recordError(ctx, baseTags, "upstream_failure")
		h.obsv.LogAndReportError(ctx, err, "agenthttp.Handler failed to sign commit via upstream API")
		http.Error(w, http.StatusText(http.StatusBadGateway), http.StatusBadGateway)
		return
	}

	resp := signCommitResponse{
		Signature: signature,
	}

	respBytes, err := json.Marshal(resp)
	if err != nil {
		logger.WithError(err).Error("failed to encode sign commit response")
		h.recordError(ctx, baseTags, "encoding_failed")
		h.obsv.LogAndReportError(ctx, err, "agenthttp.Handler failed to encode signCommit response")
		http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(respBytes)

	h.obsv.Increment(ctx, "agenthttp.handler.sign_commit", baseTags.Merge(stats.Tags{"success": "true"}))
}

// coAuthorTrailer holds the parsed components of a Co-authored-by trailer.
type coAuthorTrailer struct {
	name   string // display name before the email
	email  string // email address inside angle brackets
	userID int64  // numeric GitHub user ID; 0 if not a noreply email
	login  string // GitHub login from noreply email; empty if not a noreply email
}

// knownBotLogins contains GitHub logins for well-known bots whose
// Co-authored-by trailers are treated as informational and skipped
// during validation (they are not the job initiator).
// All entries must be lowercase; lookups use strings.ToLower for
// case-insensitive matching.
var knownBotLogins = map[string]bool{
	"copilot": true,
}

// allowedInformationalEmails contains email addresses for known AI/bot
// attribution trailers that are treated as informational and skipped
// during validation.  These are not GitHub accounts and pose no spoofing
// risk.  All entries must be lowercase; lookups use strings.ToLower for
// case-insensitive matching.
var allowedInformationalEmails = map[string]bool{
	"noreply@anthropic.com": true,
}

// isBot returns true when the trailer's login belongs to a well-known bot
// (e.g. Copilot) or follows GitHub's bot account naming convention with a
// [bot] suffix (e.g. google-labs-jules[bot]).
func (t coAuthorTrailer) isBot() bool {
	lower := strings.ToLower(t.login)
	return knownBotLogins[lower] || strings.HasSuffix(lower, "[bot]")
}

// isHumanGitHubCoAuthor returns true when the trailer represents a GitHub
// noreply co-author that should be validated against the job initiator.
// Trailers without a parsed userID (non-noreply emails) and trailers
// belonging to bots are not human co-authors.
func (t coAuthorTrailer) isHumanGitHubCoAuthor() bool {
	return t.userID != 0 && !t.isBot()
}

// isInformational returns true when the trailer is purely informational
// and should be skipped during co-author validation.  This includes:
//   - Non-noreply emails in the allowed AI attribution list
//   - GitHub noreply emails belonging to bots (well-known logins or [bot] suffix)
func (t coAuthorTrailer) isInformational() bool {
	if t.userID == 0 {
		return allowedInformationalEmails[strings.ToLower(t.email)]
	}
	return t.isBot()
}

// parseCoAuthorTrailers extracts Co-authored-by trailers from the trailing
// footer block of a raw git commit object and returns them as structured data.
// Preferentially, only the body (after the first blank line) is scanned so
// that git object headers are not accidentally matched; if no header/body
// separator exists, the entire payload is treated as the body. Only the final
// non-empty paragraph is considered so body text that mentions Co-authored-by
// is ignored.
//
// For noreply emails ({id}+{login}@users.noreply.github.com) the numeric user
// ID is parsed; non-noreply emails leave userID as 0.
//
// Returns an error if any trailer is malformed or uses a legacy noreply format.
func parseCoAuthorTrailers(payload string) ([]coAuthorTrailer, error) {
	const suffix = "@users.noreply.github.com"
	const trailerPrefix = "Co-authored-by:"
	var trailers []coAuthorTrailer

	// Extract the commit message body after the first blank line, skipping
	// git object headers (tree, parent, author, committer). If no blank line
	// separator is present, treat the entire payload as the body.
	body := payload
	if idx := strings.Index(payload, "\n\n"); idx >= 0 {
		body = payload[idx+2:]
	}

	lines := strings.Split(body, "\n")
	footerEnd := len(lines)
	for footerEnd > 0 && strings.TrimSpace(lines[footerEnd-1]) == "" {
		footerEnd--
	}

	footerStart := footerEnd
	for footerStart > 0 && strings.TrimSpace(lines[footerStart-1]) != "" {
		footerStart--
	}

	for _, line := range lines[footerStart:footerEnd] {
		trimmed := strings.TrimRight(line, " \t\r")
		if len(trimmed) < len(trailerPrefix) || !strings.EqualFold(trimmed[:len(trailerPrefix)], trailerPrefix) {
			continue
		}

		start := strings.Index(trimmed, "<")
		end := strings.Index(trimmed, ">")
		if start < 0 || end <= start {
			return nil, goerrors.Errorf("malformed Co-authored-by trailer: %q", trimmed)
		}

		// Reject lines with multiple angle-bracket pairs or non-whitespace after '>'.
		if strings.ContainsAny(trimmed[end+1:], "<>") || strings.TrimSpace(trimmed[end+1:]) != "" {
			return nil, goerrors.Errorf("malformed Co-authored-by trailer: unexpected content after email in %q", trimmed)
		}

		colonIdx := strings.Index(trimmed, ":")
		name := ""
		if colonIdx >= 0 {
			name = strings.TrimSpace(trimmed[colonIdx+1 : start])
		}

		email := trimmed[start+1 : end]
		var userID int64
		var login string

		if len(email) >= len(suffix) && strings.EqualFold(email[len(email)-len(suffix):], suffix) {
			local := email[:len(email)-len(suffix)]
			plusIdx := strings.Index(local, "+")
			if plusIdx < 1 {
				return nil, goerrors.Errorf("co-author email %q uses legacy format without numeric ID", email)
			}

			var err error
			userID, err = strconv.ParseInt(local[:plusIdx], 10, 64)
			if err != nil {
				return nil, goerrors.Errorf("co-author email %q has invalid numeric ID: %w", email, err)
			}
			login = local[plusIdx+1:]
		}

		trailers = append(trailers, coAuthorTrailer{name: name, email: email, userID: userID, login: login})
	}

	return trailers, nil
}

// validateSingleCoAuthor returns an error if more than one distinct human
// GitHub noreply Co-authored-by trailer is present.  Zero trailers is valid
// (e.g. org-billed sessions may not include a co-author).  Informational
// trailers (allowed AI attribution emails and well-known bot logins like
// Copilot) are not counted.  Duplicate trailers with the same email are
// treated as a single co-author and allowed through.
func validateSingleCoAuthor(trailers []coAuthorTrailer) error {
	// Build a case-insensitive set of distinct human GitHub noreply emails.
	// Informational trailers (allowed AI attribution emails and well-known
	// bot logins) are excluded from the single-co-author constraint.
	distinct := make(map[string]struct{}, len(trailers))
	for _, t := range trailers {
		if t.isHumanGitHubCoAuthor() {
			distinct[strings.ToLower(t.email)] = struct{}{}
		}
	}
	if len(distinct) > 1 {
		return goerrors.New("at most one GitHub Co-authored-by trailer is allowed")
	}

	return nil
}

// validateCoAuthorMatchesInitiator checks that, when a human GitHub noreply
// co-author trailer is present, it matches the job initiator.  If no
// trailers are present the check is skipped (org-billed sessions may omit
// the co-author).  Informational trailers (allowed AI attribution emails
// and well-known bot logins like Copilot) are skipped.  Non-noreply emails
// that are not in the allowed informational list are rejected.
// The human GitHub noreply co-author must contain a numeric user ID which
// is compared against job.ActorID.
func validateCoAuthorMatchesInitiator(trailers []coAuthorTrailer, job *jobs.Job) error {
	var githubTrailers []coAuthorTrailer
	for _, t := range trailers {
		if t.isInformational() {
			continue
		}
		if t.isHumanGitHubCoAuthor() {
			githubTrailers = append(githubTrailers, t)
			continue
		}
		// Non-noreply email not in the allowed informational list — reject it.
		return goerrors.Errorf("co-author email %q does not conform to the @users.noreply.github.com format", t.email)
	}

	if len(githubTrailers) == 0 {
		return nil
	}

	for _, t := range githubTrailers {
		if t.userID == job.ActorID {
			return nil
		}
	}

	coAuthorIDs := make([]int64, 0, len(githubTrailers))
	for _, t := range githubTrailers {
		coAuthorIDs = append(coAuthorIDs, t.userID)
	}
	return goerrors.Errorf("co-author exists but not matching the job initiator: co-author user IDs %v, expected actor ID %d", coAuthorIDs, job.ActorID)
}
