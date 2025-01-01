package ghinternal

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"

	gherr "github.com/github/launch/clients/github/errors"
	"github.com/github/launch/clients/github/ratelimit"
)

const (
	resolveActionOpName = "ResolveAction"
)

var ErrActionNotFound = errs.New("The requested Action could not be found")

type ResolvedAction struct {
	Name                  string `json:"name"`
	ResolvedName          string `json:"resolved_name"`
	ResolvedSha           string `json:"resolved_sha"`
	TarURL                string `json:"tar_url"`
	ZipURL                string `json:"zip_url"`
	Version               string `json:"version"`
	Visibility            string `json:"visibility"`
	PackageVersion        string `json:"package_version"`
	PackageManifestDigest string `json:"package_manifest_digest"`
}

func (c *ghclient) ResolveAction(ctx context.Context, nwo string, version types.GitRef, workflowRunID int64, jobID string, repositoryID uint64) (*ResolvedAction, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	path := fmt.Sprintf("repos/%s/actions/resolve/%s", nwo, url.QueryEscape(version.String()))
	q := make(url.Values)
	q.Set("workflowRunId", strconv.FormatInt(workflowRunID, 10))
	q.Set("jobId", jobID)
	// This repositoryID corresponds to the ID of repository containing the workflow that is being run.
	q.Set("workflowRepoId", strconv.FormatUint(repositoryID, 10))
	u := url.URL{Path: path, RawQuery: q.Encode()}

	fullAction := fmt.Sprintf("%s@%s", nwo, version.String())

	action := &ResolvedAction{}
	err := c.do(ctx, resolveActionOpName, http.MethodGet, u.String(), nil, &action, func(res *http.Response) (bool, error) {
		retryable := res.StatusCode >= 500
		if res.StatusCode >= 400 {
			return retryable, c.handleGitHubErrorResponse(ctx, res, fullAction)
		}
		return retryable, nil
	})
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	// If the original action name doesn't match up with what we are returned as
	// the response action name, we probably have a redirect repo response.
	// We're unable to do this within dotcom cleanly, so we can do it here.
	if !strings.EqualFold(action.Name, nwo) {
		action.Name = strings.ToLower(nwo)
	}

	return action, nil
}

func (c *ghclient) handleGitHubErrorResponse(ctx context.Context, r *http.Response, action string) error {
	if ratelimit.RateLimited(r.StatusCode, r.Header) {
		ratelimit.ReportRateLimiting(ctx, c.obs, r, resolveActionOpName, true)
		return NewAPIError(r.StatusCode, fmt.Sprintf("API rate limit exceeded while resolving action `%s`.", action))
	}

	errorResponse := &gherr.ErrorResponse{}
	err := json.NewDecoder(r.Body).Decode(errorResponse)
	if err != nil {
		c.obs.Error(ctx, errs.Wrap(err, "error decoding action error response").Error())
		return NewAPIError(r.StatusCode, "Internal Server Error")
	}

	errMessage := errorResponse.Message
	if errMessage == "Not Found" {
		// This is returned when the repository is missing, since we don't have
		// access to the NWO, it will just return a generic "Not Found" error.
		errMessage = fmt.Sprintf("Unable to resolve action `%s`, repository not found", action)
	}

	if r.StatusCode == http.StatusForbidden {
		c.obs.Error(ctx, "received 403 forbidden while resolving action", kvp.Err(errs.New(errorResponse.Message)))
	}

	return NewAPIError(r.StatusCode, errMessage)
}
