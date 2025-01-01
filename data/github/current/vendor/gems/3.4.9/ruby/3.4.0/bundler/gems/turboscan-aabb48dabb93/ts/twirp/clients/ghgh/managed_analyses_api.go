// Package ghgh contains Twirp clients for connecting to github/github.
package ghgh

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	api "github.com/github/turboscan/ts/monolith_twirp/managed_analyses/v1"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
	twirp "github.com/twitchtv/twirp"
)

type WorkflowRunState struct {
	Status     string
	Conclusion string
}

type ManagedAnalysesAPI interface {
	// CancelQueuedRuns cancels those of the given runs that are still queued and
	// returns the status and the conclusion of all runs.
	// Note that since cancelling is delayed runs that have ben cancelled by this call will still show as queued
	// in the return values.
	CancelQueuedRuns(ctx context.Context, repoID ts.RepositoryEID, workflowRunIDs []ts.WorkflowRunEID) (map[ts.WorkflowRunEID]WorkflowRunState, error)

	// AreRequiredServicesEnabled returns whether if the required services are enabled for the given repository and the updated
	// Actions Installation ID for the repository.
	AreRequiredServicesEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, *ts.ProximaTenant, ts.CodeqlPacks, error)

	// SkipCheckForPR skips the CodeQL check for the given PR.
	SkipCheckForPR(ctx context.Context, repoID ts.RepositoryEID, prID uint64) error

	// GetCodeScanningBotInfo gets the data of the Code Scanning Bot
	// Returns the GRID and the login
	GetCodeScanningBotInfo(ctx context.Context) (*ts.ActorGRIDLogin, error)

	// IsCodeQLRequired checks to see if the monolith thinks CodeQL should be run on this ref
	IsCodeQLRequired(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref) (bool, error)
}

type managedAnalysesAPI struct {
	client api.ManagedAnalysesAPI
	logger log.Logger
	stats  stats.Client
}

// NewManagedAnalysesAPI returns the twirp client for the ManagedAnalysesAPI TWIRP service
func NewManagedAnalysesAPI(client api.ManagedAnalysesAPI, logger log.Logger, stats stats.Client) ManagedAnalysesAPI {
	return &managedAnalysesAPI{
		client: client,
		logger: logger,
		stats:  stats,
	}
}

// CancelQueuedRuns cancels those of the given runs that are still queued and
// returns the status and the conclusion of all runs.
// Note that since cancelling is delayed runs that have ben cancelled by this call will still show as queued
// in the return values.
// NOTE: this doc is duplicated in the interface definition at the top of this file. If you make changes please update both places
func (ma *managedAnalysesAPI) CancelQueuedRuns(ctx context.Context, repoID ts.RepositoryEID, workflowRunIDs []ts.WorkflowRunEID) (map[ts.WorkflowRunEID]WorkflowRunState, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Convert the workflowRunIDs to uint64s
	ids := make([]uint64, len(workflowRunIDs))
	for i, id := range workflowRunIDs {
		ids[i] = uint64(id)
	}

	// Call the API
	req := &api.CancelQueuedRunsRequest{
		RepositoryId:  uint64(repoID),
		WorkflowRunId: ids,
	}
	resp, err := ma.client.CancelQueuedRuns(ctx, req)
	if err != nil {
		return nil, err
	}

	// Create the map from the returned values
	m := make(map[ts.WorkflowRunEID]WorkflowRunState)
	for _, s := range resp.WorkflowRunStatus {
		if s.Error != "" {
			ma.logger.Error("Error when cancelling workflow run",
				ts.WorkflowRunEID(s.WorkflowRunId).AsKVP(),
				kvp.String("gh.turboscan.error", s.Error),
			)
		} else {
			m[ts.WorkflowRunEID(s.WorkflowRunId)] = WorkflowRunState{
				Status:     s.Status,
				Conclusion: s.Conclusion,
			}
		}
	}

	return m, err
}

// AreRequiredServicesEnabled queries gh/gh and checks if all the required services (GHAS and Actions) are enabled
func (ma *managedAnalysesAPI) AreRequiredServicesEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, *ts.ProximaTenant, ts.CodeqlPacks, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	req := &api.AreRequiredServicesEnabledRequest{RepositoryId: uint64(repoID)}
	resp, err := ma.client.AreRequiredServicesEnabled(ctx, req)
	if err != nil {
		var twErr twirp.Error
		if errors.As(err, &twErr) && twErr.Code() == twirp.NotFound {
			return false, nil, ts.CodeqlPacks(""), ts.ErrRepoNotFound
		}
		return false, nil, ts.CodeqlPacks(""), err
	}

	enabled := resp.Enabled
	tenant := &ts.ProximaTenant{
		Slug: resp.TenantSlug,
		ID:   resp.TenantId,
	}

	codeqlPacks := resp.CodeqlPacks

	return enabled, tenant, ts.CodeqlPacks(codeqlPacks), nil
}

func (ma *managedAnalysesAPI) SkipCheckForPR(ctx context.Context, repoID ts.RepositoryEID, prID uint64) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	req := &api.CreateCheckForPRRequest{RepositoryId: uint64(repoID), PullRequestId: prID}
	_, err := ma.client.CreateCheckForPR(ctx, req)
	if err != nil {
		var twerr twirp.Error
		if errors.As(err, &twerr) {
			if twerr.Code() == twirp.Aborted && twerr.Msg() == "repo is not enabled for code-scanning" {
				return ts.ErrGHASDisabled
			}
		}
		return errors.Wrap(err, "error creating check for PR")
	}
	return nil
}

func (ma *managedAnalysesAPI) GetCodeScanningBotInfo(ctx context.Context) (*ts.ActorGRIDLogin, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	req := &api.GetCodeScanningBotInfoRequest{}
	res, err := ma.client.GetCodeScanningBotInfo(ctx, req)
	if err != nil {
		return nil, errors.Wrap(err, "error getting the Code Scanning bot info")
	}
	return &ts.ActorGRIDLogin{GRID: ts.ActorGRID(res.Grid), Login: res.Login}, nil
}

func (ma *managedAnalysesAPI) IsCodeQLRequired(ctx context.Context, repoID ts.RepositoryEID, ref ts.Ref) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	req := &api.IsCodeQLRequiredRequest{RepositoryId: uint64(repoID), Ref: ref}

	start := time.Now()
	var err error
	defer func() {
		ma.stats.DistributionMs("IsCodeQLRequired", nil, time.Since(start))
	}()

	res, err := ma.client.IsCodeQLRequired(ctx, req)
	if err != nil {
		return false, errors.Wrap(o11y.AnnotateError(err, repoID.AsKVP(), ref.AsKVP()), "error checking if we should scan ref")
	}
	return res.Required, nil
}
