// Package suggestedfixes contains methods related to Suggesed Fixes
package suggestedfixes

import (
	"context"
	"fmt"
	"time"

	"github.com/SamuelTissot/sqltime"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"

	"github.com/pkg/errors"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cocofix"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sf "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
)

const MySQLDuplicateEntryErrorCode = 1062

type SuggestedFixes struct {
	FixGenerator         ts.FixGenerator
	DbService            *sf.Service
	AlertService         *alert.Service
	ArchiveService       *archiver.Service
	SpokesClient         spokes.Spokes
	GitHubTwirpApiClient ghgh.SuggestedFixesAPI
	LimitsSelector       *limits.LimitSelector

	SyncUpdate SyncUpdateFn

	FixedAlertPublisher                 AutofixFixedAlertPublisher
	AutofixUsagePublisher               AutofixUsagePublisher
	AutofixGeneratePublisher            AutofixGeneratePublisher
	DependabotAutofixResultPublisher    DependabotAutofixResultPublisher
	AutofixGenerationCompletedPublisher AutofixGenerationCompletedPublisher
}

func New(db *sf.Service, as *alert.Service, archiver *archiver.Service, ls *limits.LimitSelector, sc spokes.Spokes, fixGenerator ts.FixGenerator) *SuggestedFixes {
	return &SuggestedFixes{
		DbService:      db,
		AlertService:   as,
		ArchiveService: archiver,
		LimitsSelector: ls,
		SpokesClient:   sc,
		FixGenerator:   fixGenerator,
	}
}

type SyncUpdateFn func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32)

type AutofixFixedAlertPublisher interface {
	AutofixFixedAlertEvent(context.Context, *tshydro.AutofixFixedAlertEvent) error
}

type AutofixUsagePublisher interface {
	AutofixUsageEvent(context.Context, *tshydro.AutofixUsageEvent) error
}

type AutofixGeneratePublisher interface {
	AutofixGenerateEventBatch(context.Context, []*tshydro.AutofixGenerateEvent) error
}

type DependabotAutofixResultPublisher interface {
	PublishDependabotAutofixResult(context.Context, *tshydro.DependabotAutofixResult) error
}

type AutofixGenerationCompletedPublisher interface {
	AutofixGenerationCompletedEvent(context.Context, *tshydro.AutofixGenerationCompleted) error
}

func (s *SuggestedFixes) GetSuggestedFixAlert(ctx context.Context, sfaID ts.SuggestedFixAlertID, opt *ts.FindOptions) (*ts.SuggestedFixAlert, error) {
	return s.DbService.GetSuggestedFixAlert(ctx, sfaID, opt)
}

func (s *SuggestedFixes) GetSuggestedFixAlerts(ctx context.Context, repoID ts.RepositoryEID, numbers []uint32, refs [][]byte) ([]ts.SuggestedFixAlert, error) {
	sfas, err := s.DbService.GetSuggestedFixAlerts(ctx, repoID, numbers, refs)
	if err != nil {
		// let's see if we have any suggested fixes we have been awaiting for "too long"
		stalenessThreshold := 2 * time.Hour
		for _, sfa := range sfas {
			if sfa.State == ts.SuggestedFixAlertStatePending {
				timePending := time.Since(sfa.RequestedAt.Time)
				if timePending > stalenessThreshold {
					appctx.Logger(ctx).Info("couldn't serve SuggestedFixAlert, still pending!", repoID.AsKVP(), sfa.ID.AsKVP(), kvp.Int("time_pending", int(timePending)))
					appctx.Stats(ctx).DistributionMs("sfa_fetched_pending", stats.Tags{}, timePending)
				}
			}
		}
	}

	return sfas, err
}

// CreateSuggestedFixAlert creates new SuggestedFixAlertt with associated SuggestedFix and SuggestedFix.Files if any
func (s *SuggestedFixes) CreateSuggestedFixAlert(ctx context.Context, sfa *ts.SuggestedFixAlert) error {
	err := s.DbService.CreateSuggestedFix(ctx, sfa)
	if err != nil {
		appctx.Logger(ctx).Info("failed to save fix into db",
			kvp.String("error", err.Error()),
		)
	}

	return nil
}

func (s *SuggestedFixes) GenerateSuggestedFix(ctx context.Context, sfaID ts.SuggestedFixAlertID, commit ts.Sha, tool ts.ToolName, toolVersion string, userID uint64, workload ts.ThrottlerWorkload, isCampaign bool) error {
	// 1. Get the existing SFA
	sfa, err := s.GetSuggestedFixAlert(ctx, sfaID, nil)
	if err != nil {
		// DV: I don't think this should return an error, that will cause the job to retry
		return err
	}

	repoID := sfa.RepositoryID

	ctx = appctx.With(ctx,
		kvp.Uint64("gh.turboscan.suggested_fix_alert_id", uint64(sfa.ID)),
		kvp.Stringer("gh.turboscan.suggested_fix_alert_state", sfa.State),
	)

	// 2. Check if the SFA is still pending
	if !sfa.State.IsPending() {
		appctx.Logger(ctx).Info("SuggestedFixAlert found but not in pending state")
		appctx.Stats(ctx).Counter(workload.ProcessedMetric(), stats.Tags{"workload": workload.String(), "error": "false", "exists": "true"}, 1)
		return nil // The SFA already went through the generation process, so no work is needed
	}

	findOpts := &ts.FindOptions{
		Preloads: []string{"LogicalAlert",
			"Analysis",
			"LastSeenAnalysis",
			"Rule",
		},
	}

	// load most recent physical alert
	pa, err := s.GetMostRecentPhysicalAlert(ctx, repoID, sfa.RefBytes, sfa.LogicalAlertNumber, findOpts)
	if err != nil {
		return err
	}
	targetAnalysis := pa.Analysis
	if pa.IsFixed {
		targetAnalysis = pa.LastSeenAnalysis
	}
	codeflows, locations, err := s.ArchiveService.ExtractCodePaths(ctx, targetAnalysis, []*ts.LogicalAlert{pa.LogicalAlert})
	if err != nil {
		return err
	}
	pa.CodeFlowsDocument = codeflows[pa.LogicalAlert.ID]
	pa.RelatedLocations = locations[pa.LogicalAlert.ID]

	sfa.PhysicalAlert = pa

	// 3. Try to generate a fix
	fixRes, err := s.FixGenerator.GenerateFix(ctx, tool, toolVersion, sfa, s.DownloadFunc(repoID, commit), userID, workload, isCampaign)
	if err != nil {
		if cocofix.IsNonRetriableError(err) {
			appctx.Logger(ctx).WithError(err).Error(err.Error(),
				repoID.AsKVP(),
				commit.AsKVP(),
				kvp.Uint64("physical_alert_id", uint64(pa.ID)),
				kvp.Uint64("alert_number", uint64(sfa.LogicalAlertNumber)),
			)

			// Report non-retriable errors to Sentry
			payload := map[string]string{
				"repository_id":          fmt.Sprintf("%d", repoID),
				"commit_oid":             commit.String(),
				"suggested_fix_alert_id": fmt.Sprintf("%d", sfaID),
				"integration":            ts.CapiIntegrationCodeScanning.String(),
			}
			appctx.Report(ctx, err, payload)

			err := s.UpdateSFAState(ctx, sfa, ts.SuggestedFixAlertStateError, nil, nil)
			if err != nil {
				// If we haven't managed to update the state of the SFA to error then we want to retry this if possible
				// so we don't report the processed metric here, instead we let the error bubble up.
				return errors.Wrap(err, "could not update the SFA as error after receiving a NonRetriableError")
			}
			processedTags := stats.Tags{"workload": workload.String(), "cocofix_error": "true", "error": "true", "new": "true", "state": ts.SuggestedFixAlertStateError.String()}
			appctx.Stats(ctx).Counter(workload.ProcessedMetric(), processedTags, 1)
			stateChangeDurationTags := stats.Tags{"workload": workload.String(), "state": string(ts.SuggestedFixAlertStateError), "state_before": string(sfa.State), "error": "true", "cocofix_error": "true"}
			appctx.Stats(ctx).DistributionMs(workload.StateChangeDurationMetric(), stateChangeDurationTags, time.Since(sfa.CreatedAt.Time))

			appctx.Logger(ctx).Info("NonRetriableError from CoCoFix, but successfully updated SFA as error")

			return nil
		}

		// If it was not a NonRetriableError we are assuming it is a transient error. This assumption could be wrong
		return errors.Wrap(err, "error while trying to generate a suggested fix")
	}

	// 4. Check the GenerateFix response
	if fixRes.SuggestedFixAlertState == ts.SuggestedFixAlertStateValid {
		err := s.UpdateSFAState(ctx, sfa, fixRes.SuggestedFixAlertState, nil, fixRes.SuggestedFix)
		if err != nil {
			return errors.Wrap(err, "could not update the SFA with the generated fix")
		}
		appctx.Stats(ctx).Counter(workload.ProcessedMetric(), stats.Tags{"workload": workload.String(), "error": "false", "new": "true", "state": fixRes.SuggestedFixAlertState.String()}, 1)
		stateChangeDurationTags := stats.Tags{"workload": workload.String(), "state": string(fixRes.SuggestedFixAlertState), "state_before": string(sfa.State), "error": "false", "new": "true"}
		appctx.Stats(ctx).DistributionMs(workload.StateChangeDurationMetric(), stateChangeDurationTags, time.Since(sfa.CreatedAt.Time))

		return nil
	}

	if fixRes.SuggestedFixAlertState == ts.SuggestedFixAlertStateInvalid {
		err := s.UpdateSFAState(ctx, sfa, fixRes.SuggestedFixAlertState, nil, nil)
		if err != nil {
			return errors.Wrap(err, "could not update the SFA with the invalid fix")
		}

		appctx.Stats(ctx).Counter(workload.ProcessedMetric(), stats.Tags{"workload": workload.String(), "error": "false", "new": "true", "state": fixRes.SuggestedFixAlertState.String()}, 1)
		stateChangeDurationTags := stats.Tags{"workload": workload.String(), "state": string(fixRes.SuggestedFixAlertState), "state_before": string(sfa.State), "error": "false", "new": "true"}
		appctx.Stats(ctx).DistributionMs(workload.StateChangeDurationMetric(), stateChangeDurationTags, time.Since(sfa.CreatedAt.Time))

		return nil
	}

	// This should not happen, but it can, since the type of fixRes.SuggestedFixAlertState is the generic SFA state
	// It should be changed so it can respond with valid/invalid
	return errors.New("Unexpected state in GenerateFix response")
}

// PhysicalAlertsByAlertNumbersAndRefs returns the physical alerts that need to be fixed.
func (s *SuggestedFixes) PhysicalAlertsByAlertNumbersAndRefs(ctx context.Context, repoID ts.RepositoryEID, refs [][]byte, alertNumbers []uint32, opts *ts.FindOptions) ([]*ts.PhysicalAlert, error) {
	if len(alertNumbers) == 0 {
		return nil, nil
	}

	analysisFilter := ts.AnalysisFilter{
		ExcludeFork:  true,
		State:        ts.AnalysisStateFilterMostRecent,
		RepositoryID: repoID,
		Refs:         refs,
	}

	return s.AlertService.PhysicalAlertsByAlertNumbers(ctx, repoID, alertNumbers, analysisFilter, opts)
}

func (s *SuggestedFixes) GetMostRecentPhysicalAlert(ctx context.Context, repoID ts.RepositoryEID, ref []byte, alertNumber uint32, opts *ts.FindOptions) (*ts.PhysicalAlert, error) {
	refs := [][]byte{ref}
	analysisFilter := ts.AnalysisFilter{
		ExcludeFork:  true,
		State:        ts.AnalysisStateFilterMostRecent,
		RepositoryID: repoID,
		Refs:         refs,
	}
	opts.Pagination = &ts.Pagination{Limit: uint32(1)}

	alerts, err := s.AlertService.PhysicalAlertsByAlertNumbers(ctx, repoID, []uint32{alertNumber}, analysisFilter, opts)
	if err != nil {
		return nil, err
	}
	if len(alerts) != 1 {
		return nil, errors.Errorf("Should get exactly 1 physical alert, but got %d", len(alerts))
	}

	return alerts[0], nil
}

func (s *SuggestedFixes) DownloadFunc(repoID ts.RepositoryEID, commit ts.Sha) ts.DownloadFilesFunc {
	fc := s.LimitsSelector.GetLimits(repoID).SuggestedFixesDownloadFilesLimit
	return func(ctx context.Context, filepath string) ([]byte, error) {
		fc -= 1
		if fc < 0 {
			return nil, errors.New("Downloaded more files than the limit allowed.")
		}
		return s.SpokesClient.GetFile(ctx, repoID, spokes.Filename(filepath), spokes.CommitOID(commit))
	}
}

// ApplySuggestedFix marks a SuggestedFixAlert as applied
func (s *SuggestedFixes) ApplySuggestedFix(ctx context.Context, repoID ts.RepositoryEID, number uint32, refs [][]byte, appliedBy ts.UserEID) error {
	logicalNums := []uint32{number}
	sfas, err := s.DbService.GetSuggestedFixAlerts(ctx, repoID, logicalNums, refs)
	if err != nil {
		return err
	}

	if len(sfas) == 0 {
		return errors.New("No fix found")
	}

	return s.UpdateSFAState(ctx, &sfas[0], ts.SuggestedFixAlertStateApplied, &appliedBy, nil)
}

func (s *SuggestedFixes) UpdateSFAState(ctx context.Context, sfa *ts.SuggestedFixAlert, newState ts.SuggestedFixAlertState, actorId *ts.UserEID, sf *ts.SuggestedFix) error {

	currentState := sfa.State
	sfa.SetState(newState, nil)

	sfa.StateUpdatedActorId = actorId
	sfa.SuggestedFix = sf

	err := s.DbService.UpdateSFA(ctx, sfa)
	if err != nil {
		return err
	}

	if currentState.IsPending() {
		now := time.Now()
		difference := now.Sub(sfa.RequestedAt.Time).Seconds()

		err := s.AutofixGenerationCompletedPublisher.AutofixGenerationCompletedEvent(ctx, &tshydro.AutofixGenerationCompleted{
			RepositoryId:       int64(sfa.RepositoryID),
			LogicalAlertNumber: int32(sfa.LogicalAlertNumber),
			AnalysisRef:        sfa.RefBytes,
			SfaId:              int64(sfa.ID),
			GenerationTime:     int64(difference),
		})
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("failed to emit hydro stats for autofix generation completed event")
		}
	}
	return nil
}

// IsFixOutdated checks if a suggested fix is outdated in the given commit
func (s *SuggestedFixes) IsFixOutdated(ctx context.Context, sf *ts.SuggestedFix, commit ts.Sha) (bool, error) {
	ctx, span := o11y.StartSpan(ctx,
		trace.WithAttributes(
			attribute.Int("gh.turboscan.suggested_fix.files", len(sf.Files)),
		),
	)
	defer span.End()

	d := s.DownloadFunc(sf.RepositoryID, commit)

	for _, f := range sf.Files {
		// Get the current version of the file
		fileContent, err := d(ctx, f.FilePath)
		if err != nil {
			appctx.Logger(ctx).Error("error downloading file from spokes", kvp.String("file", f.FilePath))
			if errors.Is(err, spokes.ErrFileNotFound) {
				return true, nil
			}
			return false, err
		}

		// Check if the current version still has the same checksum as when the fix was created
		checkSum := ts.BuildFileChecksum(fileContent)
		if checkSum != f.FileChecksum {
			return true, nil
		}
	}

	return false, nil
}

type CreateSFAsForAlertsResponse struct {
	// sfa ids for which SuggestedFixAlertGenerateJob will be enqueued
	GenerateFixForSfaIds map[ts.PhysicalAlertID]ts.SuggestedFixAlertID
	PhysicalAlerts       map[ts.PhysicalAlertID]*ts.PhysicalAlert
	// used for logging
	SkippedAlerts     []uint64
	SfaExistForAlerts []uint64
}

// CreateSFAsForAlerts creates SuggestedFixAlerts with pending|ruleNotSupported state for given alerts
func (s *SuggestedFixes) CreateSFAsForAlerts(ctx context.Context, repoID ts.RepositoryEID, refsBytes [][]byte, alertNumbers []uint32, requestedAt sqltime.Time) (CreateSFAsForAlertsResponse, error) {
	lt := s.LimitsSelector.GetLimits(repoID)
	findOpts := &ts.FindOptions{
		Preloads: []string{"LogicalAlert", "LogicalAlert.Rule", "LogicalAlert.Rule.Tool", "Analysis", "Analysis.ToolVersion"},
		// SC: make it configurable
		Pagination: &ts.Pagination{Limit: uint32(lt.SuggestedFixesLimit)},
	}
	var emptyRes CreateSFAsForAlertsResponse

	// 1. find all physical alerts given alert numbers and refs
	// SC: it will load max 20 physical alerts sort by default order, we should fix this to load most recent physical alert per logical alert and ref
	physicalAlerts, err := s.PhysicalAlertsByAlertNumbersAndRefs(
		ctx,
		repoID,
		refsBytes,
		alertNumbers,
		findOpts,
	)
	if err != nil {
		return emptyRes, err
	}
	var res CreateSFAsForAlertsResponse
	res.PhysicalAlerts = make(map[ts.PhysicalAlertID]*ts.PhysicalAlert, len(physicalAlerts))
	res.PhysicalAlerts = transforms.IndexBy(physicalAlerts, func(a *ts.PhysicalAlert) ts.PhysicalAlertID { return a.ID })

	// 2. find SFAs for given alert numbers and refBytes
	sfas, err := s.DbService.GetSuggestedFixAlerts(ctx, repoID, alertNumbers, refsBytes)
	if err != nil {
		return emptyRes, err
	}
	sfaByAlertNum := make(map[uint32]ts.SuggestedFixAlert, len(sfas))
	for _, sfa := range sfas {
		// SC: edge case - we may have multiple SFAs per logical alert number (when user uploads same analysis for different refs i.e. refs/pull/x/head, refs/pull/x/merge, refs/heads/branch-x)
		// we do similar mapping in GetSuggestedFix endpoint!
		sfaByAlertNum[sfa.LogicalAlertNumber] = sfa
	}

	// 3. filter out pa for which there is valid SFAs
	res.GenerateFixForSfaIds = make(map[ts.PhysicalAlertID]ts.SuggestedFixAlertID, len(physicalAlerts))
	generateFixForPhysicalAlerts := []*ts.PhysicalAlert{}
	for _, pa := range physicalAlerts {
		aNum := pa.LogicalAlert.Number
		sfa, ok := sfaByAlertNum[aNum]
		if !ok {
			generateFixForPhysicalAlerts = append(generateFixForPhysicalAlerts, pa)
			continue
		}

		switch sfa.State {
		case ts.SuggestedFixAlertStatePending:
			// If the SFA is still pending mark it for enqueuing the generation job
			res.GenerateFixForSfaIds[pa.ID] = sfa.ID
		case ts.SuggestedFixAlertStateError:
			generateFixForPhysicalAlerts = append(generateFixForPhysicalAlerts, pa)
		case ts.SuggestedFixAlertStateValid:
			outdated, err := s.IsFixOutdated(ctx, sfa.SuggestedFix, pa.Analysis.CommitOid)
			if err != nil {
				return emptyRes, err
			}
			if outdated {
				generateFixForPhysicalAlerts = append(generateFixForPhysicalAlerts, pa)
			}
		case ts.SuggestedFixAlertStateApplied, ts.SuggestedFixAlertStateInvalid, ts.SuggestedFixAlertStateRuleNotSupported, ts.SuggestedFixAlertStateValidMissingDep:
			// ignore all these states, can't use default case as go-linter looks for exhaustive switch cases
			continue
		}
	}

	// 4. create pending sfa
	for _, pa := range generateFixForPhysicalAlerts {
		sfa := &ts.SuggestedFixAlert{
			RepositoryID:        pa.RepositoryID,
			LogicalAlertNumber:  pa.LogicalAlert.Number,
			PhysicalAlert:       pa,
			RefBytes:            pa.Analysis.Ref,
			RuleSarifIdentifier: pa.LogicalAlert.SarifIdentifier,
			RequestedAt:         requestedAt,
		}
		sfa.SetState(ts.SuggestedFixAlertStatePending, nil)

		if !cocofix.ShouldGenerateFixForRule(ctx, repoID, pa.LogicalAlert) {
			sfa.SetState(ts.SuggestedFixAlertStateRuleNotSupported, nil)
		}

		err = s.DbService.CreateSuggestedFix(ctx, sfa)
		if err != nil {
			return emptyRes, err
		}

		if sfa.State.IsPending() {
			// will enqueue job
			res.GenerateFixForSfaIds[pa.ID] = sfa.ID
		} else if sfa.State.IsNotSupported() {
			// won't enqueue job
			res.SkippedAlerts = append(res.SkippedAlerts, uint64(pa.LogicalAlert.Number))
		}
	}

	return res, nil
}

func (s *SuggestedFixes) UpdateSuggestionUsage(ctx context.Context, sfa *ts.SuggestedFixAlert,
	totalAdded, totalAddedChanges int32) (float64, error) {
	suggestionUsage := 0.0
	if totalAdded != 0 {
		suggestionUsage = 1.0 - float64(totalAddedChanges)/float64(totalAdded)
	}

	sfa.SuggestionUsage = &suggestionUsage
	return suggestionUsage, s.DbService.UpdateSFA(ctx, sfa)
}

func (s *SuggestedFixes) GetAllSuggestedFixAlertsByRefs(ctx context.Context, repoID ts.RepositoryEID, refs [][]byte) ([]ts.SuggestedFixAlert, error) {
	return s.DbService.GetAllSuggestedFixAlertsByRefs(ctx, repoID, refs)
}
