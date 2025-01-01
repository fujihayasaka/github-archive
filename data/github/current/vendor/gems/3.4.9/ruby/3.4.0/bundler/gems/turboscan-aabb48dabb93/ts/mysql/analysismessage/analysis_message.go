// Package analysismessage writes messages that will appear on the tool status page.
package analysismessage

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/turboscan/ts/appctx"

	"github.com/jinzhu/gorm"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
)

// Service handles interactions with AnalysisMessages.
type Service struct {
	db *gorm.DB
}

// NewService creates an analysis message service with the given parameters
func NewService(db *gorm.DB) *Service {
	as := &Service{
		db: db,
	}
	return as
}

func (s *Service) createAnalysisMessage(ctx context.Context, a *ts.Analysis, args ts.AnalysisMessageArgs) (*ts.AnalysisMessage, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("gh.turboscan.add_analysis_message", a.Tool.CanonicalName.AsKVP(), kvp.String("key", string(args.Key())))
	appctx.Stats(ctx).Counter("gh.turboscan.add_analysis_message", stats.Tags{"third-party": fmt.Sprint(a.Tool.CanonicalName != "CodeQL"), "key": string(args.Key())}, 1)

	return s.createMessage(ctx, a.RepositoryID, &a.ID, a.DeliveryID, args)
}

func (s *Service) createDeliveryMessage(ctx context.Context, d *ts.Delivery, args ts.AnalysisMessageArgs) (*ts.AnalysisMessage, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("gh.turboscan.add_analysis_message", kvp.String("key", string(args.Key())))
	appctx.Stats(ctx).Counter("gh.turboscan.add_analysis_message", stats.Tags{"key": string(args.Key())}, 1)

	return s.createMessage(ctx, d.RepositoryID, nil, d.ID, args)
}

// createMessage is a helper used by createAnalysisMessages and createDeliveryMessage and should not be called directly.
func (s *Service) createMessage(ctx context.Context, repoId ts.RepositoryEID, analysisId *ts.AnalysisID, deliveryId ts.DeliveryID, args ts.AnalysisMessageArgs) (*ts.AnalysisMessage, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	key := args.Key()

	rawArgs, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}

	m := &ts.AnalysisMessage{
		RepositoryID: repoId,
		AnalysisID:   analysisId,
		DeliveryID:   deliveryId,
		Key:          key,
		Args:         args,
		RawArgs:      rawArgs,
	}

	err = db.Create(m).Error
	if err != nil {
		return nil, err
	}

	return m, nil
}

// SarifExecutionUnsuccessful adds a message to the Analysis indicating that the SARIF file
// contained an Invocation with an ExecutionSuccessful property with a value of false.
func (s *Service) SarifExecutionUnsuccessful(ctx context.Context, a *ts.Analysis, exitCode int, exitCodeDescription string) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifExecutionUnsuccessfulArgs{
		ExitCode:            fmt.Sprint(exitCode),
		ExitCodeDescription: ts.Truncate(exitCodeDescription, 4096),
	})
}

func (s *Service) SarifProcessingSoftLimitExceeded(ctx context.Context, a *ts.Analysis, errs []limits.LimitError) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifProcessingSoftLimitExceededArgs{
		Limits: transforms.Map(errs, func(err limits.LimitError) ts.SarifProcessingSoftLimitExceededArg {
			return ts.SarifProcessingSoftLimitExceededArg{
				Name:    err.Name,
				Dropped: err.Dropped,
				Max:     err.Max,
			}
		}),
	})
}

func (s *Service) SarifProcessingSoftLimitExceededResultsPerRun(ctx context.Context, a *ts.Analysis, le limits.LimitError) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitResultsPerRunArgs{
		Total: le.Total,
		Limit: le.Max,
	})
}

func (s *Service) SarifProcessingSoftLimitExceededThreadFlows(ctx context.Context, a *ts.Analysis, le limits.LimitError) (*ts.AnalysisMessage, error) {
	exampleCount := len(le.RuleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitThreadFlowsArgs{
		MaxThreadFlowsCount:   le.Total,
		Limit:                 le.Max,
		AlertCount:            le.AlertCount,
		ExampleRuleSarifIds:   le.RuleSarifIds[:exampleCount],
		ThreadFlowsAboveLimit: len(le.RuleSarifIds),
	})
}

func (s *Service) SarifProcessingSoftLimitExceededTagsPerRule(ctx context.Context, a *ts.Analysis, le limits.LimitError) (*ts.AnalysisMessage, error) {
	exampleCount := len(le.RuleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitTagsPerRuleArgs{
		MaxRuleTagsCount:    le.Total,
		Limit:               le.Max,
		ExampleRuleSarifIds: le.RuleSarifIds[:exampleCount],
		RulesAboveLimit:     len(le.RuleSarifIds),
	})
}

func (s *Service) SarifProcessingSoftLimitExceededRelatedLocationsPerResult(ctx context.Context, a *ts.Analysis, le limits.LimitError) (*ts.AnalysisMessage, error) {
	exampleCount := len(le.RuleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitRelatedLocationsPerResultArgs{
		MaxRelatedLocationsCount:   le.Total,
		Limit:                      le.Max,
		AlertCount:                 le.AlertCount,
		RelatedLocationsAboveLimit: len(le.RuleSarifIds),
		ExampleRuleSarifIds:        le.RuleSarifIds[:exampleCount],
	})
}

func (s *Service) SarifProcessingSoftLimitExtractedFiles(ctx context.Context, a *ts.Analysis, status bool) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitExtractedFilesStatusArgs{
		ExtractedStatus: status,
	})
}

func (s *Service) SarifSoftLimitNotExtractedFilesMessagesArgs(ctx context.Context, a *ts.Analysis, limit, count int) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifSoftLimitNotExtractedFilesMessagesArgs{
		Limit:        limit,
		MessageCount: count,
	})
}

func (s *Service) SarifProcessingHardLimitExceededRelatedLocationsPerResult(ctx context.Context, d *ts.Delivery, maxLocationCount, alertCount int, ruleSarifIds []string, limit int) (*ts.AnalysisMessage, error) {
	exampleCount := len(ruleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitRelatedLocationsPerResultArgs{
		MaxRelatedLocationsCount:   maxLocationCount,
		Limit:                      limit,
		AlertCount:                 alertCount,
		RelatedLocationsAboveLimit: len(ruleSarifIds),
		ExampleRuleSarifIds:        ruleSarifIds[:exampleCount],
	})
}

func (s *Service) SarifProcessingHardLimitExceededRuns(ctx context.Context, d *ts.Delivery, runCount int, runLimit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitRunsArgs{
		RunCount: runCount,
		RunLimit: runLimit,
	})
}

func (s *Service) SarifProcessingHardLimitExceededToolExtensions(ctx context.Context, d *ts.Delivery, maxExtensionCount int, extensionLimit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitToolExtensionsArgs{
		Limit:          extensionLimit,
		ExtensionCount: maxExtensionCount,
	})
}

func (s *Service) SarifProcessingHardLimitExceededTagsPerRule(ctx context.Context, d *ts.Delivery, ruleSarifIds []string, maxRuleTagCount int, limit int) (*ts.AnalysisMessage, error) {

	exampleCount := len(ruleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitTagsPerRuleArgs{
		ExampleRuleSarifIds: ruleSarifIds[:exampleCount],
		RulesAboveLimit:     len(ruleSarifIds),
		Limit:               limit,
		MaxRuleTagsCount:    maxRuleTagCount,
	})
}

func (s *Service) SarifProcessingHardLimitExceededThreadFlowLocations(ctx context.Context, d *ts.Delivery, ruleSarifIds []string, highestCount int, limit int) (*ts.AnalysisMessage, error) {
	exampleCount := len(ruleSarifIds)
	if exampleCount > 3 {
		exampleCount = 3
	}

	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitThreadFlowsArgs{
		MaxThreadFlowsCount:   highestCount,
		Limit:                 limit,
		ExampleRuleSarifIds:   ruleSarifIds[:exampleCount],
		ThreadFlowsAboveLimit: len(ruleSarifIds),
	})
}

func (s *Service) SarifProcessingHardLimitExceededResultsPerRun(ctx context.Context, d *ts.Delivery, resultCount int, limit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitResultsPerRunArgs{
		ResultCount: resultCount,
		Limit:       limit,
	})
}

func (s *Service) SarifProcessingHardLimitExceededRulesPerRun(ctx context.Context, d *ts.Delivery, ruleCount int, limit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifHardLimitRulesPerRunArgs{
		RuleCount: ruleCount,
		Limit:     limit,
	})
}
func (s *Service) CodeQLNotification(ctx context.Context, a *ts.Analysis, shortDescText string, id string, msgText string, msgMarkdown string, level string, helpLinks []string, locations []*ts.AnalysisMessageLocation) (*ts.AnalysisMessage, error) {
	return s.createAnalysisMessage(ctx, a, ts.SarifCodeQLNotificationArgs{
		ShortDescriptionText: shortDescText,
		Id:                   id,
		MessageText:          msgText,
		MessageMarkdown:      msgMarkdown,
		Level:                level,
		HelpLinks:            helpLinks,
		Locations:            locations,
	})
}

func (s *Service) SarifRunsMergeIgnoredUnsuccessful(ctx context.Context, d *ts.Delivery, toolName string) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifRunsMergeIgnoredUnsuccessfulArgs{
		ToolName: toolName,
	})
}

func (s *Service) SarifParsingFailed(ctx context.Context, d *ts.Delivery, errorMsg string) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifParsingFailedArgs{
		Error: errorMsg,
	})
}

func (s *Service) InvalidZip(ctx context.Context, d *ts.Delivery, empty bool) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.ZipInvalidArgs{
		Empty: empty,
	})
}

func (s *Service) SarifTooBig(ctx context.Context, d *ts.Delivery, maxVal string) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifTooBigArgs{
		Max: maxVal,
	})
}

func (s *Service) ZipTooBig(ctx context.Context, d *ts.Delivery, maxVal string) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.ZipTooBigArgs{
		Max: maxVal,
	})
}

func (s *Service) SarifNoRuns(ctx context.Context, d *ts.Delivery) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.SarifNoRunsArgs{})
}

func (s *Service) DefaultSetupRejectedUpload(ctx context.Context, d *ts.Delivery) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.DefaultSetupRejectedUploadArgs{})
}

func (s *Service) LogicalAlertsHardLimitExceeded(ctx context.Context, d *ts.Delivery, limit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.LogicalAlertsHardLimitExceededArgs{
		Limit: limit,
	})
}

func (s *Service) LogicalAlertsSoftLimitExceeded(ctx context.Context, d *ts.Delivery, hardLimit int, limit int) (*ts.AnalysisMessage, error) {
	return s.createDeliveryMessage(ctx, d, ts.LogicalAlertsSoftLimitExceededArgs{
		Limit:     limit,
		HardLimit: hardLimit,
	})
}
