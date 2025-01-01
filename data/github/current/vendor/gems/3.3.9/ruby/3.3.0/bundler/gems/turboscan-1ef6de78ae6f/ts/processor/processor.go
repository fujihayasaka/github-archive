// Package processor contains the logic for analysing new deliveries.
package processor

import (
	"bytes"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"
	"time"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/turboscan/ts/archivalstore"
	"github.com/github/turboscan/ts/auditlog"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/o11y"
	"github.com/google/uuid"
	"github.com/simon-engledew/pipereader"

	"github.com/github/turboscan/ts/flipper"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"golang.org/x/exp/maps"
	"golang.org/x/exp/slices"

	"github.com/SamuelTissot/sqltime"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/alerts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/proto"
	tssarif "github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/store"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/github/turboscan/ts/transforms"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
)

// IsMaxQueryError returns true if the error contains a vitess error when sending too large a message.
func IsMaxQueryError(err error) bool {
	return strings.Contains(err.Error(), "vttablet: rpc error: code = ResourceExhausted desc = grpc: trying to send message larger than max")
}

type Processor struct {
	as              *alert.Service
	analysisCreator AnalysisCreator
	deliveryCreator DeliveryCreator
	ams             *analysismessage.Service
	ss              SarifStore
	archivalStore   archivalstore.ArchivalStore
	toolS           *tool.Service
	configurationS  *configuration.Service
	rs              *rule.Service
	timelineS       *timeline.Service
	repos           *repository.Service
	repoapi         ghgh.RepositoryAPI
	ls              *limits.LimitSelector
	// AlertEventHandler will be use to publish alert events
	aeh ts.AlertEventHandler
	// maEnablementChecker will be used to check whether the repo
	// is using managed analyses, and eventually block the delivery.
	maEnablementChecker MAEnablementChecker

	// RuleMetadataAugmentor augments rule data in deliveries with default metadata embedded in Turboscan
	rma tssarif.RuleMetadataAugmentor
	// Service for enqueuing jobs
	jobs aqueduct.JobPerformer
}

// SarifStore provides a method for uploading and downloading SARIF files.
type SarifStore interface {
	// Download retrieves a SARIF file from the given URI into a buffer
	Download(ctx context.Context, uri string) (*bytes.Buffer, error)

	// Upload saves a SARIF file to the given URI
	Upload(ctx context.Context, sarif io.Reader, path string) error

	// Check returns an error if the downloader is not configured correctly.
	Check(ctx context.Context) error
}

type AnalysisCreator interface {
	// CreateAnalysis saves the analysis without any alerts. Alternate tool IDs can be specified if a tool was renamed
	// so that baseline analyses are carried across to the new tool.
	CreateAnalysis(ctx context.Context, analysis *ts.Analysis, alternateToolIDs ...ts.ToolID) error

	// CommitAnalysis marks the analysis as complete.
	CommitAnalysis(ctx context.Context, current *ts.Analysis) error
}

type DeliveryCreator interface {
	// CreateDelivery saves the delivery.
	CreateDelivery(ctx context.Context, delivery *ts.Delivery) error

	// CompleteDelivery marks the delivery as complete.
	CompleteDelivery(ctx context.Context, d *ts.Delivery) error
}

type MAEnablementChecker interface {
	IsEnabled(ctx context.Context, repoID ts.RepositoryEID) (bool, error)
}

func New(alert *alert.Service, analysisCreator AnalysisCreator, deliveryCreator DeliveryCreator, ams *analysismessage.Service, sarif SarifStore, archivalStore archivalstore.ArchivalStore, tool *tool.Service, configuration *configuration.Service, rule *rule.Service, timeline *timeline.Service, repos *repository.Service, repoapi ghgh.RepositoryAPI, ls *limits.LimitSelector, rma tssarif.RuleMetadataAugmentor, maEnablementChecker MAEnablementChecker, aeh ts.AlertEventHandler, jobs aqueduct.JobPerformer) *Processor {
	return &Processor{
		as:                  alert,
		analysisCreator:     analysisCreator,
		deliveryCreator:     deliveryCreator,
		ams:                 ams,
		ss:                  sarif,
		archivalStore:       archivalStore,
		toolS:               tool,
		configurationS:      configuration,
		rs:                  rule,
		timelineS:           timeline,
		repos:               repos,
		repoapi:             repoapi,
		ls:                  ls,
		rma:                 rma,
		maEnablementChecker: maEnablementChecker,
		aeh:                 aeh,
		jobs:                jobs,
	}
}

func (p *Processor) Check(ctx context.Context) error {
	return p.ss.Check(ctx)
}

func (p *Processor) SetRepositoryAPI(api ghgh.RepositoryAPI) {
	p.repoapi = api
}

func (p *Processor) failDelivery(ctx context.Context, d *ts.Delivery) {
	d.Failed = true
	deliveryErr := p.deliveryCreator.CompleteDelivery(ctx, d)
	if deliveryErr != nil {
		appctx.Logger(ctx).Error(
			fmt.Sprintf("Failed to update failed delivery: %s", deliveryErr),
			d.ID.AsKVP(),
			d.RepositoryID.AsKVP(),
		)
	}
}

func (p *Processor) ProcessNewDelivery(ctx context.Context, d *ts.Delivery) ([]*ts.Analysis, error) {
	ctx, span := o11y.StartSpan(ctx, trace.WithAttributes(attribute.Int(d.ID.AsKVP().Key, int(d.ID))))
	defer span.End()
	defer p.duration(ctx, "process-new-delivery")()

	// Re-add the request ID from the original analysis upload to the context.
	ctx = requestid.WithGitHubRequestID(ctx, string(d.RequestID))

	err := p.deliveryCreator.CreateDelivery(ctx, d)
	if err != nil {
		p.failDelivery(ctx, d)
		return nil, p.saveUnrecoverableError(ctx, d, err)
	}

	var analyses []*ts.Analysis

	runs, err := p.fetchSarifRuns(ctx, d)
	if err != nil {
		p.failDelivery(ctx, d)
		return nil, p.saveUnrecoverableError(ctx, d, err)
	}

	for _, run := range runs {
		a, err := p.processResultsForRun(ctx, d, run)
		if err != nil {
			p.failDelivery(ctx, d)
			if d.MarksAsOutdated() {
				appctx.Stats(ctx).Counter("processor.outdated_delivery_failed", nil, 1)
			}
			return nil, p.saveUnrecoverableError(ctx, d, err)
		}

		deliveryErr := p.deliveryCreator.CompleteDelivery(ctx, d)
		if deliveryErr != nil {
			return nil, p.saveUnrecoverableError(ctx, d, deliveryErr)
		}

		analyses = append(analyses, a)
	}

	return analyses, nil
}

// combineRunsKey represents the criteria for us to combine multiple runs.
type combineRunsKey struct {
	name            string
	fullName        string
	version         string
	semanticVersion string
	guid            string
	autoID          string
}

// fetchSarifRuns will download the SARIF file and
// return a map keyed by the tool name, and the values would be a slice of Run.
// Internally, we also enforce the size limit for the file, gather statistics, and
// augment the rules.
func (p *Processor) fetchSarifRuns(ctx context.Context, d *ts.Delivery) ([]*v2_1_0.Run, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	sarif, err := p.downloadAndDecodeSarif(ctx, d)
	if err != nil {
		return nil, err
	}

	// Log some stats on the file, and reject large files
	sarifStats := logSarifStats(ctx, sarif)
	if limitsForRepo, enabled := p.ls.GetHardLimits(d.RepositoryID); enabled {
		// soft limits only used here for logical alert limit check
		softLimits := p.ls.GetLimits(d.RepositoryID)
		laHardLimitExceeded, laSoftLimitExceeded, err := p.as.CheckLogicalAlertLimits(ctx, d.RepositoryID, limitsForRepo.LogicalAlertLimit, softLimits.LogicalAlertLimit)
		if err != nil {
			return nil, err
		}

		if laHardLimitExceeded {
			_, amsErr := p.ams.LogicalAlertsHardLimitExceeded(ctx, d, limitsForRepo.LogicalAlertLimit)
			if amsErr != nil {
				appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
			}
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "rejecting delivery as the repository has too many logical alerts")
		}

		if laSoftLimitExceeded {
			_, amsErr := p.ams.LogicalAlertsSoftLimitExceeded(ctx, d, limitsForRepo.LogicalAlertLimit, softLimits.LogicalAlertLimit)
			if amsErr != nil {
				appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
			}
		}

		if rejection := rejectLargeSarif(sarifStats, &limitsForRepo); rejection != nil {
			tags := stats.Tags{"has_codeql_tool": strconv.FormatBool(hasCodeQL(sarif)), "too_many_entries_type": rejection.violationType}
			appctx.Stats(ctx).Counter("processor.sarif.too_many_entries", tags, 1)

			var ruleSarifIds []string
			switch rejection.violationType {
			case "locations":
				ruleSarifIds, resultCount := tssarif.FindRuleSarifIdsForResults(ctx, sarif, func(r *v2_1_0.Result) bool {
					return len(r.Locations) > limitsForRepo.LocPerResLimit
				})
				_, amsErr := p.ams.SarifProcessingHardLimitExceededRelatedLocationsPerResult(ctx, d, rejection.value, resultCount, ruleSarifIds, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "runs":
				_, amsErr := p.ams.SarifProcessingHardLimitExceededRuns(ctx, d, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "tags":
				ruleSarifIds = tssarif.FindRuleSarifIds(sarif, func(r *v2_1_0.Rule) bool {
					return r.Properties != nil && len(r.Properties.Tags) > rejection.limit
				})
				_, amsErr := p.ams.SarifProcessingHardLimitExceededTagsPerRule(ctx, d, ruleSarifIds, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "steps":
				ruleSarifIds, _ = tssarif.FindRuleSarifIdsForResults(ctx, sarif, func(r *v2_1_0.Result) bool {
					for _, codeFlow := range r.CodeFlows {
						for _, threadFlow := range codeFlow.ThreadFlows {
							if threadFlow.Locations != nil && len(threadFlow.Locations) > rejection.limit {
								return true
							}
						}
					}
					return false
				})

				_, amsErr := p.ams.SarifProcessingHardLimitExceededThreadFlowLocations(ctx, d, ruleSarifIds, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "extensions":
				_, amsErr := p.ams.SarifProcessingHardLimitExceededToolExtensions(ctx, d, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "results":
				_, amsErr := p.ams.SarifProcessingHardLimitExceededResultsPerRun(ctx, d, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			case "rules":
				_, amsErr := p.ams.SarifProcessingHardLimitExceededRulesPerRun(ctx, d, rejection.value, rejection.limit)
				if amsErr != nil {
					appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
				}
			}

			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, fmt.Sprintf("rejecting SARIF, as there are %s", rejection.Error()))
		}
	}

	combinedRuns := make(map[combineRunsKey]struct{})

	// SplitRuns returns a map of Tool to Run
	runs := make(map[combineRunsKey]*v2_1_0.Run)
	for _, run := range sarif.Runs {
		if run.Tool == nil {
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "Run is missing a tool property")
		}
		if run.Tool.Driver == nil {
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "Tool is missing a driver property")
		}
		// Check whether the repo is enabled for managed analysis, and if so reject any
		// deliveries that has a non-managed analysis for CodeQL
		shouldBlock, err := shouldBlockAnalysis(ctx, p.maEnablementChecker, ts.ToToolName(run.Tool.Driver.Name), d.AnalysisKey, d.RepositoryID, d.MarksAsOutdated())
		if err != nil {
			return nil, err
		}
		if shouldBlock {
			_, amsErr := p.ams.DefaultSetupRejectedUpload(ctx, d)
			if amsErr != nil {
				appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
			}

			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "CodeQL analyses from advanced configurations cannot be processed when the default setup is enabled")
		}

		// Do not allow outdated runs to contain results
		if d.MarksAsOutdated() && len(run.Results) > 0 {
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "An outdated delivery cannot contain results")
		}

		runKey := combineRunsKey{
			name:            run.Tool.Driver.Name,
			fullName:        run.Tool.Driver.FullName,
			version:         run.Tool.Driver.Version,
			semanticVersion: run.Tool.Driver.SemanticVersion,
			guid:            run.Tool.Driver.Guid,
			autoID:          tssarif.GetAutomationID(run),
		}

		if oldR, ok := runs[runKey]; ok {
			combinedRuns[runKey] = struct{}{}

			// Only merge runs that have an equal success status
			// otherwise discard the unsuccessful one and add a message to the delivery.
			switch {
			case run.HasUnsuccessfulInvocations() == oldR.HasUnsuccessfulInvocations():
				run, err = oldR.Merge(run)
				if err != nil {
					return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, err.Error())
				}
			case run.HasUnsuccessfulInvocations() && oldR.HasOnlySuccessfulInvocations():
				d.Failed = true
				run = oldR
				_, err = p.ams.SarifRunsMergeIgnoredUnsuccessful(ctx, d, run.Tool.Driver.Name)
				if err != nil {
					return nil, err
				}
			case run.HasOnlySuccessfulInvocations() && oldR.HasUnsuccessfulInvocations():
				d.Failed = true
				// just keep run unchanged
				_, err = p.ams.SarifRunsMergeIgnoredUnsuccessful(ctx, d, oldR.Tool.Driver.Name)
				if err != nil {
					return nil, err
				}
			}

		}
		runs[runKey] = run
	}

	// Augment runs with default data
	for _, run := range runs {
		// This call modifies the run in-place
		err = p.rma.AugmentDefaultRuleData(run)
		if err != nil {
			return nil, err
		}
	}

	// Experiment to see how often we are combining runs
	if len(combinedRuns) > 0 {
		appctx.Stats(ctx).Counter("processor.sarif.combined_run", nil, 1)

		toolAndIdNames := transforms.Map(maps.Keys(combinedRuns), func(k combineRunsKey) string {
			version := k.semanticVersion
			if version == "" {
				version = k.version
			}
			if version == "" {
				version = "n/a"
			}
			return fmt.Sprintf("%s (%s): %s", k.name, version, k.autoID)
		})

		fields := make([]kvp.Field, 0, 2)
		fields = append(fields, kvp.String("gh.turboscan.sarif_path", d.SarifPath))
		fields = append(fields, d.RepositoryID.AsKVP())
		fields = append(fields, kvp.String("gh.turboscan.tool_and_automationids", strings.Join(toolAndIdNames, ", ")))

		appctx.Logger(ctx).Info(
			fmt.Sprintf("combining runs for: %s", d.SarifPath),
			fields...,
		)
	}
	// End experiment

	if len(runs) == 0 {
		_, amsErr := p.ams.SarifNoRuns(ctx, d)
		if amsErr != nil {
			appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
		}
		return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, "Runs are missing")
	}

	return maps.Values(runs), nil
}

func hasCodeQL(sarif *v2_1_0.SARIF210ForGitHubCodeScanning) bool {
	for _, r := range sarif.Runs {
		if r.Tool == nil || r.Tool.Driver == nil {
			continue
		}
		if r.Tool.Driver.Name == "CodeQL" {
			return true
		}
	}

	return false
}

// Downloads and decodes the SARIF file.
// Used by fetchSarifRuns.
func (p *Processor) downloadAndDecodeSarif(ctx context.Context, d *ts.Delivery) (*v2_1_0.SARIF210ForGitHubCodeScanning, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if d.MarksAsOutdated() {
		// We don't try to download the sarif for a tombstone delivery as it does not exist
		return tssarif.BuildOutdatedSarif(d.OutdatedConfiguration.ToolName, d.OutdatedConfiguration.Category)
	}

	buf, err := p.ss.Download(ctx, d.SarifPath)

	if err != nil {
		// We can't recover Uncompression errors.
		var uerr *store.UncompressError
		if errors.As(err, &uerr) {
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, uerr.Error())
		}
		// We also cannot recover from too big sarif errors
		if errors.Is(err, store.ErrMaximumSizeExceeded) {
			return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, store.ErrMaximumSizeExceeded.Error())
		}
		return nil, err
	}

	size := buf.Len()
	if size > 0 {
		appctx.Stats(ctx).Distribution("processor.sarif_mb", nil, float64(size)/1024/1024)
	}

	sarif, err := tssarif.Decode(buf.Bytes())
	if err != nil {
		// Store this as a delivery message for the status page
		// (We ignore errors about storing the error message)
		_, amsErr := p.ams.SarifParsingFailed(ctx, d, err.Error())
		if amsErr != nil {
			appctx.Logger(ctx).WithError(amsErr).Error("storing delivery error message failed")
		}

		// Parsing errors are not recoverable.
		return nil, ts.NewUnrecoverableDeliveryError(d.RepositoryID, d.SarifID, err.Error())
	}

	return sarif, nil
}

// saveUnrecoverableError will save any UnrecoverableError(ProcessError type) into the database, and return nil.
// If the cause is another type of error, it will just return it.
func (p *Processor) saveUnrecoverableError(ctx context.Context, delivery *ts.Delivery, cause error) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	var perr *ts.ProcessError
	if !errors.As(cause, &perr) {
		// If error is not a Process error, we just short-circuit and don't save it
		return cause
	}
	perr.SarifURI = delivery.SarifPath
	if perr.RepositoryID == 0 {
		perr.RepositoryID = delivery.RepositoryID
	}
	if perr.SarifID == "" {
		perr.SarifID = delivery.SarifID
	}

	return p.as.LogProcessError(ctx, perr)
}

func (p *Processor) populateAnalysisAndEvents(ctx context.Context, delivery *ts.Delivery, run *v2_1_0.Run, analysis *ts.Analysis, repository *ts.Repository) ([]*ts.TimelineEvent, map[ts.LogicalAlertID]struct{}, error) {
	err := p.populateAnalysis(ctx, run, analysis, repository, delivery.CheckoutURI)
	if err != nil {
		// This call is currently unbounded as the number of fixed alerts could keep growing.
		// We track addressing this in https://github.com/github/code-scanning/issues/7146
		// For now we do not want to retry processing if we have run into the Vitess query limit.
		if IsMaxQueryError(err) {
			return nil, nil, ts.NewUnrecoverableAnalysisError(analysis.RepositoryID, analysis, "could not fetch alerts from baseline")
		}
		return nil, nil, err
	}

	// Unpack baseline and most recent for readability
	baselineID, mostRecent := analysis.BaselineID, analysis.MostRecent

	var events []*ts.TimelineEvent
	var changedLogicalAlertIds map[ts.LogicalAlertID]struct{}
	if mostRecent {
		presentAlerts := analysis.PresentAlerts()
		baselineAlerts := analysis.BaselineAlerts

		// Diff the open and fixed alerts in the baseline to the new alerts
		openDiff, fixedDiff := alerts.CompareAlerts(baselineAlerts, presentAlerts)

		fixedAlertNumbers, err := p.getFixedAlertNumbers(ctx, analysis.RepositoryID, openDiff)
		if err != nil {
			return nil, nil, err
		}

		h := NewSuggestedFixTelemetryHandler(p.jobs)
		h.Handle(ctx, baselineAlerts, analysis, fixedAlertNumbers)

		baselineFixesToKeep := fixedDiff.Removed
		fixCopyLimit := p.ls.GetLimits(analysis.RepositoryID).FixesCopiedLimit
		if flipper.HasLimitAlertFixes(ctx, analysis.RepositoryID) && len(baselineFixesToKeep) > fixCopyLimit {
			appctx.Stats(ctx).Distribution("processor.fixes_not_copied", nil, float64(len(baselineFixesToKeep)-fixCopyLimit))
			// Select fixCopyLimit fixed alerts from the baseline for copying to the new analysis.
			// This could be optimized by avoiding to sort everything but it might be ok for now.
			slices.SortFunc[[]*ts.PhysicalAlert](baselineFixesToKeep, func(a, b *ts.PhysicalAlert) int {
				return a.CreatedAt.Compare(b.CreatedAt.Time)
			})
			baselineFixesToKeep = baselineFixesToKeep[:fixCopyLimit]

		}

		// Copy the removed alerts (that do not exist) from the baseline
		err = p.as.CopyFixedAlerts(ctx, repository, analysis, append(openDiff.Removed, baselineFixesToKeep...))
		if err != nil {
			return nil, nil, err
		}

		// Calculate logical alert IDs corresponding to changed physical alerts
		changedPhysicalAlerts := alerts.CompareAlertsMetadata(baselineAlerts, presentAlerts)

		now := sqltime.Now()
		for _, a := range changedPhysicalAlerts {
			a.LastStateChangeAt = now
		}

		// Calculate logical alert IDs corresponding to changed physical alerts
		changedLogicalAlertIds, err = p.getChangedLogicalAlertIDs(ctx, openDiff, changedPhysicalAlerts)
		if err != nil {
			return nil, nil, err
		}

		// Trigger all events for the update
		events, err = createEvents(ctx, analysis, baselineID != nil, openDiff, fixedDiff)
		if err != nil {
			return nil, nil, err
		}
		err = p.timelineS.WriteTimelineEvents(ctx, events)
		if err != nil {
			return nil, nil, err
		}

	}

	return events, changedLogicalAlertIds, nil
}

// Returns a map of logical alert IDs corresponding to changed physical alerts
// ref https://github.com/github/security-center/issues/2800
func (p *Processor) getChangedLogicalAlertIDs(ctx context.Context, openDiff alerts.AlertDiff, changedPhysicalAlerts []*ts.PhysicalAlert) (map[ts.LogicalAlertID]struct{}, error) {
	start := time.Now()
	// Combine all diffs into one array
	var changedAlerts []*ts.PhysicalAlert
	changedAlerts = append(changedAlerts, openDiff.Added...)
	changedAlerts = append(changedAlerts, openDiff.Removed...)
	changedAlerts = append(changedAlerts, changedPhysicalAlerts...)

	changedLogicalAlertIds := make(map[ts.LogicalAlertID]struct{})
	for _, physical := range changedAlerts {
		changedLogicalAlertIds[physical.LogicalAlertID] = struct{}{}
	}

	appctx.Stats(ctx).DistributionMs("processor.physical_alert_change_detection", nil, time.Since(start))

	return changedLogicalAlertIds, nil
}

func (p *Processor) getFixedAlertNumbers(ctx context.Context, repositoryID ts.RepositoryEID, openDiff alerts.AlertDiff) ([]uint32, error) {
	var fixedPhysicalAlertIDs []ts.PhysicalAlertID
	// iterate over the 'open' alerts on the baseline analysis,
	// that were removed in the current analysis (fixed alerts)
	for _, pa := range openDiff.Removed {
		fixedPhysicalAlertIDs = append(fixedPhysicalAlertIDs, pa.ID)
	}

	if len(fixedPhysicalAlertIDs) == 0 {
		return []uint32{}, nil
	}

	findOptions := &ts.FindOptions{Preloads: []string{"LogicalAlert"}}
	pas, err := p.as.PhysicalAlertByIDs(ctx, repositoryID, fixedPhysicalAlertIDs, findOptions)
	if err != nil {
		return nil, errors.Wrap(err, "Cannot find physical alerts by ID.")
	}

	var fixedAlertNumbers []uint32
	for _, pa := range pas {
		fixedAlertNumbers = append(fixedAlertNumbers, pa.LogicalAlert.Number)
	}

	return fixedAlertNumbers, nil
}

// mergeErrors returns err, using it to wrap innerErr if present.
// if err is not present innerErr will be returned instead.
func mergeErrors(err error, innerErr error) error {
	if innerErr != nil {
		if err != nil {
			return errors.Wrap(err, innerErr.Error())
		}
		return innerErr
	}

	return err
}

func (p *Processor) processResultsForRun(
	ctx context.Context,
	delivery *ts.Delivery,
	run *v2_1_0.Run) (*ts.Analysis, error) {

	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	automationID := readAutomationID(ctx, run, delivery.AnalysisKey, delivery.Environment)

	// Save the tool and all its extensions.
	driver, extensions, err := tssarif.ToolVersionsFromSarifRun(run)
	if err != nil {
		return nil, ts.NewUnrecoverableAnalysisError(delivery.RepositoryID, nil, "could not parse tools")
	}

	err = p.toolS.FindOrCreate(ctx, append(extensions, driver))
	if err != nil {
		return nil, errors.Wrap(err, "unable to update tools")
	}

	configuration := ts.Configuration{
		RepositoryID: delivery.RepositoryID,
		Ref:          delivery.Ref,
		ToolID:       driver.ToolID,
		Category:     automationID.Category,
	}
	err = p.configurationS.FindOrCreate(ctx, &configuration)
	if err != nil {
		return nil, err
	}

	sarifRules, err := tssarif.GetRules(run)
	if err != nil {
		return nil, ts.NewUnrecoverableAnalysisError(delivery.RepositoryID, nil, "could not parse rules")
	}

	// Now the tool versions are saved we can save rules.
	// We must save the tool versions first because rules have a volatile DefiningToolVersionID property which
	// requires the database ID of the tool that created it.
	rules, ruleLimitError, err := tssarif.ConvertRules(ctx, sarifRules, driver, extensions, p.ls.GetLimits(delivery.RepositoryID).TagsPerRuleLimit)
	if err != nil {
		return nil, ts.NewUnrecoverableAnalysisError(delivery.RepositoryID, nil, fmt.Sprintf("could not convert rules: %s", err))
	}

	err = p.rs.FindOrCreate(ctx, maps.Values(rules))
	if err != nil {
		return nil, errors.Wrap(err, "unable to update rules")
	}

	analysis := ts.NewAnalysis(delivery, &configuration, driver, automationID, rules)
	if ruleLimitError != nil {
		analysis.AddWarning(fmt.Sprintf("Some tags for %d rule(s) were ignored as they exceeded the limit of %d tags. One such rule is '%s'.",
			len(ruleLimitError.RuleSarifIds), ruleLimitError.Max, ruleLimitError.RuleSarifIds[0]))
	}

	analysis.DefaultQueriesDisabled, analysis.AnalysisQuerySuites = tssarif.GetCodeQLConfig(run)

	for _, v := range sarifRules {
		if v.Rule == v2_1_0.UnknownRule {
			appctx.Stats(ctx).Counter("processor.unknown_rule", nil, 1)
			appctx.Logger(ctx).Info("gh.turboscan.unknown_rule", driver.Name.AsKVP())
			// We create an 'unknown' rule if there was no corresponding rule in the sarif document.
			// We want to add a warning that the tool may be misconfigured
			analysis.AddWarning("analysis result references a rule that is not defined")
			break
		}
	}

	if analysis.Tool == nil {
		return nil, errors.New("tool not preloaded")
	}

	toolIDs, err := p.toolS.ToolsIDsWithRenames(ctx, analysis.Tool.CanonicalName)
	if err != nil {
		return nil, errors.Wrap(err, "unable to lookup tool")
	}

	err = p.analysisCreator.CreateAnalysis(ctx, analysis, toolIDs...)
	if err != nil {
		return nil, errors.Wrapf(err, "unable to create analysis for repository: %v", analysis.RepositoryID)
	}

	// Now that the analysis has been created in the db we can also store a potential limit error
	if ruleLimitError != nil {
		_, err := p.ams.SarifProcessingSoftLimitExceededTagsPerRule(ctx, analysis, *ruleLimitError)
		if err != nil {
			return nil, err
		}
	}

	analysis.SetToolVersions(append(extensions, driver))

	// for the MVP we only want to track the status of CodeQL
	// we don't want third party tools to start copying the extracted/baseline files implementation until we have
	// had a chance to iron out any details we are not happy with
	// turn off track status unless the tool is CodeQL
	delivery.TrackStatus = delivery.TrackStatus && driver.Tool.IsCodeQL()

	if delivery.TrackStatus {
		err := p.toolS.CreateAnalysisExtractedFiles(ctx, analysis, run, p.ams)
		if err != nil {
			return analysis, errors.Wrap(err, "failed to save tool status")
		}

		notExtractedFiles := ts.FileSetUnion(maps.Values(analysis.AnalysisExtractedFiles.FilesNotExtracted)...)
		if analysis.Tool.IsCodeQL() {
			toolErrors := make(map[string]*v2_1_0.Notification)

			for _, invocation := range run.Invocations {
				workingDirectory := ts.EmptyCheckoutURI
				if invocation.WorkingDirectory != nil {
					workingDirectory = ts.ToCheckoutURI(invocation.WorkingDirectory.Uri)
				}

				for _, notification := range invocation.ToolExecutionNotifications {
					if err := tssarif.GetCodeQLExtractorErrors(notification, workingDirectory, toolErrors, notExtractedFiles); err != nil {
						return analysis, errors.Wrap(err, "failed to retrieve errors for not extracted files")
					}

					if notification.Properties != nil && notification.Properties.Visibility != nil && notification.Properties.Visibility.StatusPage {
						_, reportingDescriptor, err := run.LookupNotification(notification)
						if err != nil {
							return analysis, errors.Wrap(err, "failed to get reporting descriptor for notification")
						}

						_, err = p.ams.CodeQLNotification(
							ctx,
							analysis,
							reportingDescriptor.ShortDescription.Text,
							reportingDescriptor.Id,
							notification.Message.Text,
							notification.Message.Markdown,
							notification.Level,
							notification.Properties.HelpLinks,
							tssarif.ConvertSarifNotificationLocationsToAnalysisMessageLocations(notification.Locations),
						)
						if err != nil {
							return analysis, errors.Wrap(err, "failed to save codeql notification messages")
						}
					}
				}
			}

			if err := p.toolS.CreateAnalysisExtractedFilesMessages(ctx, analysis, toolErrors, p.ams); err != nil {
				return analysis, errors.Wrap(err, "failed to save error messages for not extracted files")
			}

		}
	}

	repository, err := p.findOrCreateRepository(ctx, delivery.RepositoryID, delivery.Ref)
	if err != nil {
		return analysis, errors.Wrap(err, "failed to find or create repository")
	}

	events, changedLogicalAlertIds, err := p.populateAnalysisAndEvents(ctx, delivery, run, analysis, repository)
	if err != nil {
		analysis.Failed = true
	}
	ppStart := time.Now()
	sarifErr := p.saveProcessedSARIF(ctx, analysis)
	if sarifErr != nil {
		appctx.Logger(ctx).WithError(sarifErr).Error("Failed post processing SARIF",
			analysis.RepositoryID.AsKVP(),
			kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
		)
		analysis.Failed = true
		err = mergeErrors(err, sarifErr)
	}
	appctx.Stats(ctx).DistributionMs("pp.sarif.analysis.full", nil, time.Since(ppStart))

	err = mergeErrors(err, p.analysisCreator.CommitAnalysis(ctx, analysis))

	// this is a stop-gap while we come up with a solution for analysis with long warning messages
	// it stops the processor retrying this analysis over and over again
	if errors.Is(err, ts.ErrAnalysisProcessWarningOverflow) {
		return analysis, ts.NewUnrecoverableAnalysisError(analysis.RepositoryID, analysis, err.Error())
	}

	if err != nil {
		return analysis, err
	}

	// now this analysis has been committed clean up the previous tool status record to avoid database bloat
	if delivery.TrackStatus && analysis.BaselineID != nil {
		if err := p.toolS.DeleteAnalysisExtractedFiles(ctx, delivery.RepositoryID, *analysis.BaselineID); err != nil {
			return analysis, errors.Wrap(err, "failed to delete previous tool status")
		}

		if err := p.toolS.DeleteAnalysisExtractedFilesMessages(ctx, delivery.RepositoryID, *analysis.BaselineID); err != nil {
			return analysis, errors.Wrap(err, "failed to delete previous error messages for not extracted files")
		}
	}

	if !flipper.HasSkipAlertIndexing(ctx, analysis.RepositoryID) {
		ppStart := time.Now()

		ppErr := p.postProcess(ctx, analysis, repository, changedLogicalAlertIds)
		if ppErr != nil {
			// Elastic search errors are not fatal we should only log if it fails
			appctx.Logger(ctx).Error(
				fmt.Sprintf("Failed post processing analysis: %s", ppErr),
				analysis.RepositoryID.AsKVP(),
				kvp.Uint64("gh.turboscan.analysis_id", uint64(analysis.ID)),
			)
			appctx.Stats(ctx).Counter("pp.ingest.update.error", nil, 1)
		}
		appctx.Stats(ctx).DistributionMs("pp.ingest.analysis.full", nil, time.Since(ppStart))
	}

	auditLogContext := auditlog.AuditLogContext{
		// TODO: Fields need to be added to the Hydro message and stored on the delivery.
	}

	if len(events) > 0 && p.aeh != nil && analysis.MostRecent && !flipper.HasSkipEmittingAlertEvents(ctx, analysis.RepositoryID) {
		err = p.emitEvents(ctx, delivery.RepositoryID, analysis, events, auditLogContext)
	}
	if err != nil {
		return analysis, err
	}

	return analysis, nil
}

func (p *Processor) emitEvents(ctx context.Context, repoID ts.RepositoryEID, analysis *ts.Analysis, events []*ts.TimelineEvent, auditLogContext auditlog.AuditLogContext) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	logicalAlertIDs := transforms.MapUnique(events, func(e *ts.TimelineEvent) ts.LogicalAlertID {
		return e.LogicalAlertID
	})

	logicalAlertsByID := make(map[ts.LogicalAlertID]*ts.LogicalAlert, len(logicalAlertIDs))

	if err := gormext.Chunks(ctx, 100, len(logicalAlertIDs), func(start int, end int) error {
		chunk := logicalAlertIDs[start:end]

		filter := ts.AlertFilter{
			IDs:   chunk,
			State: proto.AlertStateFilter_ALERT_STATE_FILTER_ALL,
		}
		analysisFilter := ts.AnalysisFilter{
			RepositoryID:    repoID,
			AnalysisIDs:     []ts.AnalysisID{analysis.ID},
			IncludeOutdated: true,
		}
		options := &ts.FindOptions{
			Preloads: []string{
				"Rule",
				"Rule.Tags",
				"Rule.Tool",
				"PhysicalAlerts",
				"PhysicalAlerts.LastSeenAnalysis",
			},
			SortBy: alert.SortBy(proto.AlertSortOrder_CREATED_ASCENDING),
		}

		logicalAlerts, err := p.as.Alerts(ctx, repoID, filter, analysisFilter, options)
		if err != nil {
			return err
		}

		// reuse the analysis we already have rather than loading it again for each physical alert
		for _, la := range logicalAlerts {
			for _, pa := range la.PhysicalAlerts {
				if pa.AnalysisID != analysis.ID {
					return errors.New("loaded alerts from unexpected analysis")
				}
				pa.Analysis = analysis
			}

			logicalAlertsByID[la.ID] = la
		}

		return nil
	}); err != nil {
		return errors.Wrap(err, "failed to fetch batch of alerts")
	}

	for _, e := range events {
		// Only send the event if the logical alert exists (i.e., was not deleted)
		if la, ok := logicalAlertsByID[e.LogicalAlertID]; ok {
			err := p.aeh.NewAlertEvent(ctx, la, e, auditLogContext)
			if err != nil {
				return err
			}
		}
	}

	err := p.aeh.Flush()
	if err != nil {
		return err
	}

	return nil
}

// populateAnalysis Store Alerts and Analysis into MySQL.
func (p *Processor) populateAnalysis(
	ctx context.Context,
	run *v2_1_0.Run,
	analysis *ts.Analysis,
	repository *ts.Repository,
	checkoutURI ts.CheckoutURI,
) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	repoID := analysis.RepositoryID

	// If there are any failed invocations in a run, we should not build the alerts.
	for _, i := range run.Invocations {
		if !i.ExecutionSuccessful {
			message := fmt.Sprintf("unsuccessful execution, exit code: %d, description: %s ", i.ExitCode, i.ExitCodeDescription)

			_, err := p.ams.SarifExecutionUnsuccessful(ctx, analysis, i.ExitCode, i.ExitCodeDescription)
			if err != nil {
				appctx.Logger(ctx).WithError(err).Error("failed to save SarifExecutionUnsuccessful to DB", analysis.ID.AsKVP())
			}
			if analysis.Tool.IsCodeQL() {
				return ts.NewUnsuccessfulAnalysisError(repoID, analysis, message)
			} else {
				analysis.AddWarning(fmt.Sprintf("unsuccessful tool execution, exit code %d", i.ExitCode))
				appctx.Logger(ctx).Warn("gh.turboscan.unsuccessful_execution", analysis.Tool.CanonicalName.AsKVP(), kvp.String("message", message))
				appctx.Stats(ctx).Counter("processor.unsuccessful_execution", nil, 1)
			}
		}
	}

	// Construct alerts from SARIF - these contain holes for logical alerts.
	repoLimits := p.ls.GetLimits(repoID)
	builder := alerts.NewAlertsBuilder(analysis, &repoLimits)
	physicalAlerts, err := builder.Build(ctx, run, checkoutURI)

	// Abort processing if any of the errors were unrecoverable
	if uerr := alerts.UnrecoverableError(err); uerr != nil {
		return ts.NewUnrecoverableAnalysisError(repoID, analysis, uerr.Error())
	}

	// Save any warnings from the Builder. There will not be any unrecoverable errors here because we have already
	// checked for them above.
	for _, err := range alerts.SplitErrors(err) {
		analysis.AddWarning(err.Error())
	}

	limitErrs := alerts.LimitErrors(err)

	baselineAlerts, err := p.as.RetrieveBaselineAlerts(ctx, analysis)
	if err != nil {
		return errors.Wrap(err, "unable to retrieve baseline alerts")
	}
	analysis.BaselineAlerts = baselineAlerts

	// After this new and existing logical alerts are set on the analysis.
	err = p.as.SaveAlerts(ctx, analysis, repository, physicalAlerts)
	if err != nil {
		return err
	}

	// Set the alerts now that we have saved them to the database.
	analysis.SetPresentAlerts(physicalAlerts)

	if uerr := alerts.UnrecoverableError(err); uerr != nil {
		return ts.NewUnrecoverableAnalysisError(repoID, analysis, uerr.Error())
	}

	limitErrs = append(limitErrs, alerts.LimitErrors(err)...)

	if len(limitErrs) > 0 {
		for _, le := range limitErrs {
			switch le.AnalysisMessageKey {
			case string(ts.MessageSarifSoftLimitResultsPerRun):
				_, err := p.ams.SarifProcessingSoftLimitExceededResultsPerRun(ctx, analysis, le)
				if err != nil {
					return err
				}
			case string(ts.MessageSarifSoftLimitThreadFlows):
				_, err := p.ams.SarifProcessingSoftLimitExceededThreadFlows(ctx, analysis, le)
				if err != nil {
					return err
				}
			case string(ts.MessageSarifSoftLimitRelatedLocations):
				_, err := p.ams.SarifProcessingSoftLimitExceededRelatedLocationsPerResult(ctx, analysis, le)
				if err != nil {
					return err
				}
			}
		}
	}

	// Save any warnings from the Builder. There will not be any unrecoverable errors here because we have already
	// checked for them above.
	for _, err := range alerts.SplitErrors(err) {
		analysis.AddWarning(err.Error())
	}

	// Update rule counter and associate physical alerts
	analysis.RulesCount = uint(len(analysis.Rules))

	return nil
}

// createEvents creates all events related to the update
func createEvents(
	ctx context.Context,
	analysis *ts.Analysis,
	hasBaseline bool,
	openDiff alerts.AlertDiff,
	fixedDiff alerts.AlertDiff,
) ([]*ts.TimelineEvent, error) {

	_, span := o11y.StartSpan(ctx)
	defer span.End()

	events := []*ts.TimelineEvent{}

	newLogicalAlertsByID := make(map[ts.LogicalAlertID]*ts.LogicalAlert, len(analysis.NewLogicalAlerts))
	// create events for all unique alerts
	for _, a := range analysis.NewLogicalAlerts {
		te := &ts.TimelineEvent{
			RepositoryID:   a.RepositoryID,
			LogicalAlertID: a.ID,
			EventType:      ts.TimelineEventTypeAlertCreated,
			EventTimestamp: sqltime.Now(),
			CommitOid:      analysis.CommitOid,
			Ref:            string(analysis.Ref),
			FilePath:       a.FilePath,
			StartLine:      a.Region.StartLine,
			ToolVersionID:  analysis.ToolVersionID,
			AnalysisID:     analysis.ID,
			Environment:    analysis.Environment,
			WorkflowRunID:  analysis.WorkflowRunID,
		}
		events = append(events, te)
		newLogicalAlertsByID[a.ID] = a
	}

	// create a map of analysis.ExistingLogicalAlerts by ID for easy lookup
	existingLogicalAlertsByID := make(map[ts.LogicalAlertID]*ts.LogicalAlert, len(analysis.ExistingLogicalAlerts))
	for _, a := range analysis.ExistingLogicalAlerts {
		existingLogicalAlertsByID[a.ID] = a
	}

	// create a map of analysis.FixedLogicalAlerts by ID for easy lookup
	fixedLogicalAlertsByID := make(map[ts.LogicalAlertID]*ts.LogicalAlert, len(analysis.FixedLogicalAlerts))
	for _, a := range analysis.FixedLogicalAlerts {
		fixedLogicalAlertsByID[a.ID] = a
	}

	// All added alerts are either newly added to the branch or reappeared in the branch
	for _, pa := range openDiff.Added {
		a, ok := existingLogicalAlertsByID[pa.LogicalAlertID]
		if !ok {
			a, ok = newLogicalAlertsByID[pa.LogicalAlertID]
			if !ok {
				// This should never happen, but we want to be safe
				return nil, errors.New("unexpected state: could not find logical alert for physical alert")
			}
		}
		// If the alert did not exist in the baseline then it is completely new,
		// if it did then it reappeared
		var eventType ts.TimelineEventType
		if fixedDiff.AddedIDs[a.ID] {
			// the open alert was 'added' into the tip. Also means it was NOT fixed in the baseline
			eventType = ts.TimelineEventTypeAlertAppearedInBranch
		} else {
			// when looking at the fixed baseline alerts, the current alerts was not added.
			// it was fixed in the baseline, and now it is open (thus: not added)
			eventType = ts.TimelineEventTypeAlertReappeared
		}

		if !hasBaseline {
			_, alreadySeen := newLogicalAlertsByID[a.ID]
			if alreadySeen {
				// Don't emit a duplicate event for an alert we've already emitted an event for because it was unique.
				continue
			}
		}

		te := &ts.TimelineEvent{
			RepositoryID:   a.RepositoryID,
			LogicalAlertID: a.ID,
			EventType:      eventType,
			EventTimestamp: sqltime.Now(),
			CommitOid:      analysis.CommitOid,
			Ref:            string(analysis.Ref),
			FilePath:       a.FilePath,
			StartLine:      a.Region.StartLine,
			ToolVersionID:  analysis.ToolVersionID,
			AnalysisID:     analysis.ID,
			Environment:    analysis.Environment,
			WorkflowRunID:  analysis.WorkflowRunID,
			NonUnique:      !hasBaseline,
		}
		events = append(events, te)
	}

	// All removed alerts are closed as either fixed or outdated
	eventType := ts.TimelineEventTypeAlertClosedBecameFixed
	if analysis.IsOutdated {
		eventType = ts.TimelineEventTypeAlertClosedBecameOutdated
	}
	for _, pa := range openDiff.Removed {
		if !hasBaseline {
			_, alreadySeen := newLogicalAlertsByID[pa.LogicalAlertID]
			if alreadySeen {
				// Don't emit a duplicate event for an alert we've already emitted an event for because it was unique.
				continue
			}
		}
		a, ok := fixedLogicalAlertsByID[pa.LogicalAlertID]
		if !ok {
			// This should never happen, but we want to be safe
			return nil, errors.New("unexpected state: could not find logical alert for physical alert")
		}
		te := &ts.TimelineEvent{
			RepositoryID:   a.RepositoryID,
			LogicalAlertID: a.ID,
			EventType:      eventType,
			EventTimestamp: sqltime.Now(),
			CommitOid:      analysis.CommitOid,
			Ref:            string(analysis.Ref),
			FilePath:       a.FilePath,
			StartLine:      a.Region.StartLine,
			ToolVersionID:  analysis.ToolVersionID,
			AnalysisID:     analysis.ID,
			Environment:    analysis.Environment,
			WorkflowRunID:  analysis.WorkflowRunID,
			NonUnique:      !hasBaseline,
		}
		events = append(events, te)
	}

	return events, nil
}

type sarifMaxStats struct {
	Runs                 int
	ResPerRun            int
	RulesPerRun          int
	ToolExtensionsPerRun int
	LocPerRes            int
	StepsPerRes          int
	TagsPerRule          int
}

type sarifRejection struct {
	violationType string
	info          string
	value, limit  int
}

func (s *sarifRejection) Error() string {
	return fmt.Sprintf("more %s than allowed (%d > %d)", s.info, s.value, s.limit)
}

// logSarifStats logs various metrics associated with the SARIF file.
// Metrics that are used by the limits package are returned for applying limits.
func logSarifStats(ctx context.Context, s *v2_1_0.SARIF) sarifMaxStats {
	var totRuns, totRes, totRules, totToolExtensions, totLoc, totFlows, totSteps, totMetrics, totTags int
	var maxResPerRun, maxRulesPerRun, maxToolExtensionsPerRun, maxLocPerRes, maxFlowsPerRes, maxStepsPerFlow, maxStepsPerRes, maxMetrics, maxTagsPerRule int

	totRuns = len(s.Runs)
	for _, r := range s.Runs {
		if r.Tool != nil && r.Tool.Driver != nil {
			rulesCnt := len(r.Tool.Driver.Rules)
			toolExtensionsCount := len(r.Tool.Extensions)
			updateMax(&maxToolExtensionsPerRun, toolExtensionsCount)
			totToolExtensions += toolExtensionsCount

			for _, ext := range r.Tool.Extensions {
				rulesCnt += len(ext.Rules)

				for _, rule := range ext.Rules {
					if rule.Properties != nil {
						tagsPerRuleCount := len(rule.Properties.Tags)
						updateMax(&maxTagsPerRule, tagsPerRuleCount)
						totTags += tagsPerRuleCount
					}
				}
			}

			updateMax(&maxRulesPerRun, rulesCnt)
			totRules += rulesCnt

			for _, rule := range r.Tool.Driver.Rules {
				if rule.Properties != nil {
					tagsPerRuleCount := len(rule.Properties.Tags)
					updateMax(&maxTagsPerRule, tagsPerRuleCount)
					totTags += tagsPerRuleCount
				}
			}
		}

		resCnt := len(r.Results)
		updateMax(&maxResPerRun, resCnt)
		totRes += resCnt

		for _, res := range r.Results {
			locCnt := len(res.Locations)
			updateMax(&maxLocPerRes, locCnt)
			totLoc += locCnt
			totStepsPerRes := 0

			for _, codeFlow := range res.CodeFlows {
				flowCnt := len(codeFlow.ThreadFlows)
				updateMax(&maxFlowsPerRes, flowCnt)
				totFlows += flowCnt

				for _, threadFlow := range codeFlow.ThreadFlows {
					stepCnt := len(threadFlow.Locations)
					updateMax(&maxStepsPerFlow, stepCnt)
					totSteps += stepCnt
					totStepsPerRes += stepCnt
				}
			}
			updateMax(&maxStepsPerRes, totStepsPerRes)
		}
		if r.Properties != nil && r.Properties.MetricResults != nil {
			totMetrics += len(r.Properties.MetricResults)
			updateMax(&maxMetrics, len(r.Properties.MetricResults))
		}
	}

	appctx.Logger(ctx).Info("SARIF Stats",
		kvp.Uint64("gh.turboscan.tot_runs", uint64(totRuns)),
		kvp.Uint64("gh.turboscan.tot_res", uint64(totRes)),
		kvp.Uint64("gh.turboscan.tot_rules", uint64(totRules)),
		kvp.Uint64("gh.turboscan.tot_tags", uint64(totTags)),
		kvp.Uint64("gh.turboscan.tot_loc", uint64(totLoc)),
		kvp.Uint64("gh.turboscan.tot_flows", uint64(totFlows)),
		kvp.Uint64("gh.turboscan.tot_steps", uint64(totSteps)),
		kvp.Uint64("gh.turboscan.tot_metrics", uint64(totMetrics)),
		kvp.Uint64("gh.turboscan.tot_extensions", uint64(totToolExtensions)),
		kvp.Uint64("gh.turboscan.max_res_per_run", uint64(maxResPerRun)),
		kvp.Uint64("gh.turboscan.max_rules_per_run", uint64(maxRulesPerRun)),
		kvp.Uint64("gh.turboscan.max_tags_per_rule", uint64(maxTagsPerRule)),
		kvp.Uint64("gh.turboscan.max_loc_per_res", uint64(maxLocPerRes)),
		kvp.Uint64("gh.turboscan.max_flows_per_res", uint64(maxFlowsPerRes)),
		kvp.Uint64("gh.turboscan.max_steps_per_flow", uint64(maxStepsPerFlow)),
		kvp.Uint64("gh.turboscan.max_steps_per_res", uint64(maxStepsPerRes)),
		kvp.Uint64("gh.turboscan.max_metrics", uint64(maxMetrics)),
		kvp.Uint64("gh.turboscan.max_extensions", uint64(maxToolExtensionsPerRun)),
	)

	// Return max values to be used when applying limits
	return sarifMaxStats{
		Runs:                 totRuns,
		ResPerRun:            maxResPerRun,
		RulesPerRun:          maxRulesPerRun,
		ToolExtensionsPerRun: maxToolExtensionsPerRun,
		LocPerRes:            maxLocPerRes,
		StepsPerRes:          maxStepsPerRes,
		TagsPerRule:          maxTagsPerRule,
	}
}

func updateMax(x *int, y int) {
	if y > *x {
		*x = y
	}
}

func rejectLargeSarif(stats sarifMaxStats, t *limits.Table) *sarifRejection {

	check := func(name, nameInfo string, value, limit int) *sarifRejection {
		if value > limit {
			return &sarifRejection{
				violationType: name,
				value:         value,
				limit:         limit,
				info:          nameInfo,
			}
		}
		return nil
	}

	if rejection := check("runs", "runs", stats.Runs, t.RunsPerSarifLimit); rejection != nil {
		return rejection
	}
	if rejection := check("results", "results per run", stats.ResPerRun, t.ResPerRunLimit); rejection != nil {
		return rejection
	}
	if rejection := check("rules", "rules per run", stats.RulesPerRun, t.RulesPerRunLimit); rejection != nil {
		return rejection
	}
	if rejection := check("extensions", "tool extensions per run", stats.ToolExtensionsPerRun, t.ToolExtensionsPerRunLimit); rejection != nil {
		return rejection
	}
	if rejection := check("locations", "related locations per result", stats.LocPerRes, t.LocPerResLimit); rejection != nil {
		return rejection
	}
	if rejection := check("steps", "threadflow steps per result", stats.StepsPerRes, t.StepsPerResLimit); rejection != nil {
		return rejection
	}
	if rejection := check("tags", "tags per rule", stats.TagsPerRule, t.TagsPerRuleLimit); rejection != nil {
		return rejection
	}

	return nil
}

func readAutomationID(ctx context.Context, run *v2_1_0.Run, analysisKey ts.AnalysisKey, environment ts.AnalysisEnv) ts.AutomationID {
	// By default the category is derived from the key and env
	defaultCategory := categoryFromKeyEnv(analysisKey, environment)

	if run.AutomationDetails == nil || run.AutomationDetails.Id == "" {
		// If we cannot find the automation details we fallback on the default here
		if analysisKey == "(default)" {
			appctx.Stats(ctx).Counter("processor.category", stats.Tags{"source": "api", "present": "false"}, 1)
		} else {
			appctx.Stats(ctx).Counter("processor.category", stats.Tags{"source": "action", "present": "false"}, 1)
		}
		return ts.AutomationID{
			Category: defaultCategory,
		}
	}

	if analysisKey == "(default)" {
		appctx.Stats(ctx).Counter("processor.category", stats.Tags{"source": "api", "present": "true"}, 1)
	} else {
		appctx.Stats(ctx).Counter("processor.category", stats.Tags{"source": "action", "present": "true"}, 1)
	}

	// The ID is the last part of the string, the rest is the category
	parts := strings.Split(run.AutomationDetails.Id, "/")

	specifiedCategory := ts.ToCategory(strings.Join(parts[:len(parts)-1], "/"))
	specifiedRunID := ts.Truncate(parts[len(parts)-1], 250)

	// Log if the specified category does not match the default category
	// This is done in a transition period so that we can catch errors with the action,
	// and keep track of third party tools that use this feature.
	if defaultCategory != specifiedCategory {
		appctx.Logger(ctx).Info("AutomationRunID category difference",
			kvp.String("gh.turboscan.default_category", defaultCategory.String()),
			kvp.String("gh.turboscan.specified_category", specifiedCategory.String()),
		)
	}

	return ts.AutomationID{
		Category: specifiedCategory,
		RunID:    specifiedRunID,
	}
}

func categoryFromKeyEnv(analysisKey ts.AnalysisKey, environment ts.AnalysisEnv) ts.Category {
	// The API uses "(default)" we want to convert that to the empty category
	if analysisKey == "(default)" {
		return ""
	}
	// We sort the environment to make sure it is persisted deterministically
	keys := maps.Keys(environment)
	sort.Strings(keys)
	var env strings.Builder
	for _, k := range keys {
		env.WriteString("/" + k + ":" + environment[k])
	}

	// We combine the key and environment to form an ID
	return ts.ToCategory(analysisKey.String() + env.String())
}

func (p *Processor) duration(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		appctx.Stats(ctx).DistributionMs("processor.request", stats.Tags{"method": method}, time.Since(start))
	}
}

// shouldBlockAnalysis returns true if processing should be aborted for the specified delivery.
// This is so that we do not accept un-managed analyses together with managed ones.
func shouldBlockAnalysis(ctx context.Context, ma MAEnablementChecker, toolName ts.ToolName, analysisKey ts.AnalysisKey, repoID ts.RepositoryEID, marksAsOutdated bool) (bool, error) {
	if marksAsOutdated {
		// Outdated deliveries are always allowed through
		return false, nil
	}

	// Remember to take tool renames into account
	if renamedTool, ok := ts.CanonicalToolRenames[toolName]; ok {
		toolName = renamedTool
	}

	// Only CodeQL can be managed
	if toolName != "CodeQL" {
		return false, nil
	}
	// All managed workflows are allowed through
	if strings.HasPrefix(analysisKey.String(), ts.ManagedAnalysisWorkflowPath) {
		return false, nil
	}

	// Lookup whether the repo is managed
	ok, err := ma.IsEnabled(ctx, repoID)
	if err != nil {
		return false, err
	}
	if ok {
		// The repo is using Managed Analysis, we can should block the analysis
		return true, nil
	}

	return false, nil
}

func (p *Processor) saveProcessedSARIF(ctx context.Context, analysis *ts.Analysis) error {
	opts := tssarif.BuildSarifOpts{
		RepoHTMLURL: "$repoHtmlUrl",
		AlertAPIURL: "$alertApiUrl",
	}

	// We need to make sure Logical Alerts have their corresponding Rule set
	// in order to build the SARIF correctly
	for _, pa := range analysis.PresentAlerts() {
		for _, rule := range analysis.Rules {
			if pa.RuleID == rule.ID {
				pa.LogicalAlert.Rule = rule
			}
		}
	}

	// we only need the present phyical alerts in the SARIF
	allPhyiscalAlerts := analysis.PhysicalAlerts
	analysis.PhysicalAlerts = analysis.PresentAlerts()
	sarifString, err := tssarif.BuildSarif(analysis, opts)

	analysis.PhysicalAlerts = allPhyiscalAlerts
	if err != nil {
		return errors.Wrap(err, "failed to rebuild the SARIF")
	}

	pr := pipereader.New(strings.NewReader(sarifString), gzip.NewWriter)
	path := fmt.Sprintf("archive/%d/%s.sarif.gz", analysis.RepositoryID, uuid.NewString())

	archiveDataUrl, err := p.archivalStore.Archive(ctx, pr, path)
	if err != nil {
		return err
	}
	analysis.ArchivalDataUrl = archiveDataUrl
	return nil
}

func (p *Processor) findOrCreateRepository(ctx context.Context, repoID ts.RepositoryEID, ref []byte) (*ts.Repository, error) {
	// Fetch repository object
	repository, err := p.repos.Find(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if repository == nil || bytes.Equal(repository.DefaultRef, []byte("")) {
		// try to fetch the metadata from Twirp
		repository, err = p.fetchAndUpdateRepoMetadata(ctx, repoID)
		if err != nil {
			// If we fail at all the prior attempts, create a repository entry from the data provided
			// log here as we will not return the error
			appctx.Logger(ctx).WithError(err).Error("failed to get repository metadata via twirp", repoID.AsKVP())

			repository = &ts.Repository{
				RepositoryID:        repoID,
				CodeScanningEnabled: true,
				SourceUpdatedAt:     sqltime.Now(),
				// since we're not sure what the default ref is, we'll leave it blank for now
				DefaultRef: []byte(""),
			}
			err = p.repos.Update(ctx, repository)
			if err != nil {
				return nil, errors.Wrap(err, "failed to create ts_repositories entry")
			}
		}
	}
	return repository, err
}

func (p *Processor) fetchAndUpdateRepoMetadata(ctx context.Context, repoID ts.RepositoryEID) (*ts.Repository, error) {
	if p.repoapi == nil {
		return nil, errors.New("No RepositoryAPI configured")
	}
	repos, err := p.repoapi.GetRepositories(ctx, []ts.RepositoryEID{repoID})
	if err != nil {
		return nil, err
	}
	if len(repos) == 0 {
		return nil, errors.Errorf("repository %d not found", repoID)
	}
	err = p.repos.Update(ctx, repos[0])
	if err != nil {
		return nil, errors.Wrap(err, "failed to update repository metadata")
	}
	return repos[0], nil
}
