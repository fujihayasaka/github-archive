// Package enabled_status contains the definitions for when we consider code scanning enabled on a repository
// and helper methods related to communicating that status.
//
//   - A tool other than CodeQL is _enabled_ on a repo iff there is an active tip for the tool on the default branch. (Note that this implies the existence of a successful analysis.)
//   - CodeQL is _enabled_ on a repo _in default setup_ iff default setup is currently turned on.
//   - CodeQL is _enabled_ on a repo _in advanced setup_ iff there is an active tip for CodeQL on the default branch and any of the following holds:
//     a) CodeQL has never been enabled in default setup on the repo or
//     b) The active tip was created after default setup has most recently been disabled.
//   - We say CodeQL is enabled on a repo if it is enabled in default setup or in advanced setup.
//   - Code scanning is _enabled_ on a repo iff any tool is enabled on the repo.
package enabled_status

import (
	"bytes"
	"context"
	"strconv"
	"time"

	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/o11y"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
)

var branchRefPrefix []byte = []byte("refs/heads/")

type Publisher interface {
	EnablementEvent(_ context.Context, m *tshydro.EnablementEvent) error
}

// CodeqlRepoDB is used in place of CodeqlDB from
// github.com/github/turboscan/ts/managedanalyses
// to avoid circular dependencies.
type CodeqlRepoDB interface {
	IsEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, error)
	GetCodeqlRepo(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error)
	GetDisabledTime(ctx context.Context, repoID ts.RepositoryEID) (*time.Time, error)
}

// RepoService is used in place of Service from
// github.com/github/turboscan/ts/mysql/repository
// to avoid circular dependencies
type RepoService interface {
	Find(context.Context, ts.RepositoryEID) (*ts.Repository, error)
}

type EnabledStatusService struct {
	alertService  *alert.Service
	db            *gorm.DB
	repoService   RepoService
	maDB          CodeqlRepoDB
	publisher     Publisher
	shouldPublish bool // At present, we only publish in tests
}

func NewEnabledStatusService(db *gorm.DB, alertService *alert.Service, repoService RepoService, maDB CodeqlRepoDB, publisher Publisher, shouldPublish bool) *EnabledStatusService {
	return &EnabledStatusService{
		db:            db,
		alertService:  alertService,
		repoService:   repoService,
		maDB:          maDB,
		publisher:     publisher,
		shouldPublish: shouldPublish,
	}
}

// IsCodeQLCheckOptional checks to see if we should enforce a CodeQL scan be present when evaluating repository rules.
func (e *EnabledStatusService) IsCodeQLCheckOptional(ctx context.Context, repoID ts.RepositoryEID, isDependabot bool) (bool, error) {
	// managed analysis cannot scan isDependabot commits, so we must skip CodeQL checks
	if isDependabot {
		return e.maDB.IsEnabled(ctx, repoID)
	}
	repo, err := e.maDB.GetCodeqlRepo(ctx, repoID)
	if errors.Is(err, ts.ErrCodeqlRepoNotFound) {
		return false, nil
	}
	if repo == nil {
		return false, err
	}
	return repo.IsWaiting(), err
}

// IsCodeScanningEnabled determines whether code scanning is considered to be enabled on the given repo or not.
// See the package description for how this is defined.
func (e *EnabledStatusService) IsCodeScanningEnabled(ctx context.Context, repoID ts.RepositoryEID, defaultRef []byte) (bool, error) {
	// Get information about managed analyses
	maEnabled, err := e.maDB.IsEnabled(ctx, repoID)
	if err != nil {
		return false, err
	}
	if maEnabled {
		return true, nil
	}

	// If there is no defaultRef we cannot continue checking the status, so we assume code scanning is disabled
	if len(defaultRef) == 0 {
		return false, nil
	}

	// Get the latest tips
	filter := ts.AnalysisFilter{
		RepositoryID:    repoID,
		State:           ts.AnalysisStateFilterMostRecent,
		Refs:            [][]byte{defaultRef},
		IncludeOutdated: false,
	}

	pagination := ts.Pagination{
		Limit:  10, // We use a low limit of 10 for the first query since we expect to get an answer from one of the first results
		Offset: 0,
	}

	findOptions := &ts.FindOptions{
		Preloads:   []string{"Tool"},
		Pagination: &pagination,
		SortBy:     "ts_analyses.created_at desc, ts_analyses.id desc",
	}

	done := false
	for !done {
		if err := appctx.ContextError(ctx, "is_code_scanning_enabled"); err != nil {
			return false, err
		}

		// Read tips from the database
		analyses, err := e.alertService.FindAnalyses(ctx, filter, findOptions)
		if err != nil {
			return false, err
		}

		maDisabledTime, err := e.maDB.GetDisabledTime(ctx, repoID)
		if err != nil {
			return false, err
		}

		for _, a := range analyses {
			if a.Tool.IsCodeQL() {
				// We already know managed analyses is disabled because we checked it earlier
				// so we're only interested in this analysis if it's from advanced setup
				if a.DeliveryOrigin != ts.DeliveryOrigin_MANAGED {
					// analysis `a` is an advanced setup analysis
					// If managed analyses was never enabled or this analysis is from after when it was last disabled,
					// code scanning is enabled
					if maDisabledTime == nil || a.CreatedAt.Time.After(*maDisabledTime) {
						return true, nil
					}
				}
			} else {
				// We have a non-CodeQL tool that is active.
				// So code scanning is defined to be enabled.
				return true, nil
			}
		}

		// If we've found fewer than limit analyses in the database then there won't be any more left to retrieve.
		done = len(analyses) != int(pagination.Limit)

		if !done {
			pagination.Offset += pagination.Limit
			// We made the first request with a low limit since we expect that almost every tip causes us to return true.
			// If we got to this point then this repo seems weird: It must have a lot of CodeQL configs that we do not consider enabled.
			// We increase the limit to go through any other tips without too many database calls.
			pagination.Limit = 100
		}
	}

	// We did not find any tips that indicated enabled status so code scanning is disabled.
	return false, nil
}

// PublishStatusIfChanged checks the current enablement status of code scanning for the repo and publishes a change event
// to the Hydro topic if the observed status is different to the one that was published on the topic previously.
//
// The method takes two optional parameters for optimization:
//   - relatedRef:    Provide if you can attribute the potential change event to a certain ref. This allows quick return in case the
//     ref is not the default ref (and thus does not influence enablement state)
//   - expectedState: Provide if you know what the trigger action could have changed the state into. You do not need to know if this
//     is the new state. It's rather an expression that IF there was a change then it was to this state.
//     This allows quick return if the expectedState matches the already published state.
func (e *EnabledStatusService) PublishStatusIfChanged(ctx context.Context, repoID ts.RepositoryEID, reason ts.EnablementReason, relatedRef []byte, expectedState *bool) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	start := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("status_service.publish_status_if_changed.duration",
			stats.Tags{"refPresent": strconv.FormatBool(relatedRef != nil), "expectedStatePresent": strconv.FormatBool(expectedState != nil)},
			time.Since(start))
	}()

	if relatedRef != nil && !bytes.Equal(relatedRef[:len(branchRefPrefix)], branchRefPrefix) {
		// Only the default ref can influence the state.
		// If it is not a branch ref we can return early without accessing the db.
		return
	}

	repo, err := e.repoService.Find(ctx, repoID)
	if err != nil {
		e.logPublishingError(ctx, repoID, err, reason)
		return
	}

	if repo == nil {
		// All repos that have or used to have code scanning enabled should be in the repositories table.
		// If we do not have repo information then we consider code scanning to be not enabled.
		// Furthermore, it can never have been enabled in the past, so we do not even have to publish a disable event
		// and can just return.
		// However, unless `reason` is OBSERVED_CHANGE (which is passed by the api endpoint GetCodeScanningEnabled)
		// or `DISABLE_DEFAULT_SETUP` (which can happen without the repo being fully onboarded)
		// some code scanning activity must have triggered this code getting executed, so something might be wrong here.
		// We log an error to see if this happens.
		// We also do not log in the case of DELETED_ANALYSIS. We've seen this occur when the only analyses we have for
		// the repo are failed ones. Since the only state change that can happen from deletion is disablement this is not
		// a problem.
		if reason != ts.EnablementReason_OBSERVED_CHANGE && reason != ts.EnablementReason_DISABLE_DEFAULT_SETUP && reason != ts.EnablementReason_DELETED_ANALYSIS {
			e.logPublishingError(ctx, repoID, errors.New("repo not present in table"), reason)
		}
		return
	}

	if relatedRef != nil && !bytes.Equal(relatedRef, repo.DefaultRef) {
		// Only the default ref can influence the state.
		return
	}

	if expectedState != nil {
		publish, err := e.stateNeedsPublishing(ctx, repoID, *expectedState)
		if err != nil {
			e.logPublishingError(ctx, repoID, errors.Wrap(err, "Could not determine whether expected state needs publishing."), reason)
		} else if !publish {
			return
		}
	}

	enabled, err := e.IsCodeScanningEnabled(ctx, repoID, repo.DefaultRef)
	if err != nil {
		e.logPublishingError(ctx, repoID, err, reason)
		return
	}

	shouldPublish, err := e.stateNeedsPublishing(ctx, repoID, enabled)
	if err != nil {
		e.logPublishingError(ctx, repoID, errors.Wrap(err, "Could not determine whether state needs publishing."), reason)
		return
	}

	if shouldPublish {
		err = e.emitEnablementEvent(ctx, repoID, enabled, reason)
		if err != nil {
			e.logPublishingError(ctx, repoID, err, reason)
		}
	}
}

// PublishStatusForDefaultSetup publishes a change event to the Hydro topic
// this method should only be called for the new default setup enablement logic
func (e *EnabledStatusService) PublishStatusForDefaultSetup(ctx context.Context, repoID ts.RepositoryEID, reason ts.EnablementReason) {
	newStatus := false
	if reason == ts.EnablementReason_ENABLE_DEFAULT_SETUP {
		newStatus = true
	} else if reason != ts.EnablementReason_DISABLE_DEFAULT_SETUP {
		e.logPublishingError(ctx, repoID, errors.New("invalid reason"), reason)
	}

	err := e.emitEnablementEvent(ctx, repoID, newStatus, reason)
	if err != nil {
		e.logPublishingError(ctx, repoID, err, reason)
	}
}

// logPublishingError logs an error that happened during a publishing operation, i.e. either
// the publishing itself or during determining the status for publishing. Since publishing should
// never cause the operation that caused the status check to fail these errors are otherwise ignored
// and not returned by the Publish* methods.
func (e *EnabledStatusService) logPublishingError(ctx context.Context, repoID ts.RepositoryEID, err error, reason ts.EnablementReason) {
	appctx.Logger(ctx).WithError(err).Error("(suppressed) error in status publishing code", repoID.AsKVP(), reason.AsKVP())
	payload := map[string]string{
		"message":                        "(suppressed) error in enablement publishing code",
		"gh.repo.id":                     strconv.FormatUint(uint64(repoID), 10),
		"gh.turboscan.enablement_reason": reason.String(),
	}
	appctx.Report(ctx, err, payload)
}

func (e *EnabledStatusService) emitEnablementEvent(ctx context.Context, repoID ts.RepositoryEID, enabled bool, reason ts.EnablementReason) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if !e.shouldPublish {
		return nil
	}

	event := &tshydro.EnablementEvent{
		RepositoryId: int64(repoID),
		Enabled:      enabled,
		Reason:       reasonToHydroType(reason, enabled),
	}

	err := e.publisher.EnablementEvent(ctx, event)
	if err != nil {
		return err
	}

	err = e.savePublishedStatus(repoID, enabled, reason)
	if err != nil {
		return errors.Wrap(err, "Could not save published status.")
	}

	return nil
}

func (e *EnabledStatusService) savePublishedStatus(repoID ts.RepositoryEID, enabled bool, reason ts.EnablementReason) error {
	var existingState ts.PublishedEnabledState
	err := e.db.Where("repository_id = ?", repoID).First(&existingState).Error
	if err != nil {
		if !gorm.IsRecordNotFoundError(err) {
			return err
		}

		// Create
		p := &ts.PublishedEnabledState{
			RepositoryID: repoID,
			Enabled:      enabled,
			Reason:       reason,
		}
		err = e.db.Create(p).Error
	} else {
		// Update
		existingState.Enabled = enabled
		existingState.Reason = reason
		err = e.db.Save(&existingState).Error
	}

	if err != nil {
		return err
	}

	return nil
}

func reasonToHydroType(reason ts.EnablementReason, enabled bool) tshydro_entities.EnablementReason {
	switch reason {
	case ts.EnablementReason_ENABLE_DEFAULT_SETUP:
		return tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_SETUP
	case ts.EnablementReason_DISABLE_DEFAULT_SETUP:
		return tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_SETUP
	case ts.EnablementReason_DEFAULT_BRANCH_CHANGE:
		return tshydro_entities.EnablementReason_ENABLEMENT_REASON_DEFAULT_BRANCH_CHANGE
	case ts.EnablementReason_RECEIVED_ANALYSIS:
		if enabled {
			return tshydro_entities.EnablementReason_ENABLEMENT_REASON_RECEIVED_ANALYSIS_DEFAULT_BRANCH
		} else {
			// A received "tombstone" analysis indicates marking config as outdated
			return tshydro_entities.EnablementReason_ENABLEMENT_REASON_MARKED_CONFIG_OUTDATED
		}
	case ts.EnablementReason_DELETED_ANALYSIS:
		if enabled {
			// This should not really be happening
			return tshydro_entities.EnablementReason_ENABLEMENT_REASON_UNKNOWN
		} else {
			return tshydro_entities.EnablementReason_ENABLEMENT_REASON_DELETE_ANALYSIS_DEFAULT_BRANCH
		}
	case ts.EnablementReason_OBSERVED_CHANGE:
		return tshydro_entities.EnablementReason_ENABLEMENT_REASON_OBSERVED_CHANGE
	default:
		return tshydro_entities.EnablementReason_ENABLEMENT_REASON_UNKNOWN
	}
}

// stateNeedsPublishing returns true if the given state is different from the state
// most recently published to Hydro for the given repo.
func (e *EnabledStatusService) stateNeedsPublishing(ctx context.Context, repoID ts.RepositoryEID, state bool) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	publishedState := ts.PublishedEnabledState{}
	err := e.db.Where("repository_id = ?", repoID).First(&publishedState).Error
	if err != nil {
		if gorm.IsRecordNotFoundError(err) {
			// For cases where we have not published before the assumed previous state is implicitly 'not enabled'.
			// Ideally we would decide not to publish if `state` was false in this case, since it is not actually a status
			// change.
			// However, for purposes of switching over from the previous enabled definition that considered code scanning
			// to be enabled when any analysis existed we actually want to emit an explicit "not enabled"-event.
			// This is mostly because we want to be able to use the Hydro topic data for scoring an OKR.
			// Because of this we're checking whether any analysis exists here. (We do not want to just publish for every repo,
			// since that would grow the publishing table needlessly.)
			// It would be good to remove the check for analyses and just return `state` after sufficient time has passed,
			// let's say after Sep 2023.
			if state {
				return true, nil
			} else {
				filter := ts.AnalysisFilter{
					RepositoryID:    repoID,
					IncludeDeleted:  true,
					IncludeOutdated: true,
				}
				ex, err := e.alertService.AnalysisExists(ctx, filter)
				if err != nil {
					return false, err
				}
				return ex, err
			}

		}
		return false, err
	}

	return publishedState.Enabled != state, nil
}
