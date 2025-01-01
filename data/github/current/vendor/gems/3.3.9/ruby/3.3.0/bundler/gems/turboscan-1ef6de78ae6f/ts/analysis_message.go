package ts

import (
	"encoding/json"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/proto"
	"github.com/jinzhu/gorm"
)

type AnalysisMessageID uint64

// An AnalysisMessage represents a note, warning or error that occurred
// during the whole (or part) of an analysis, or during processing.
// These messages are not necessarily indicative of terminal failure.
//
// # Key
//
// Key is an identifier for the type of message that is used to
// determine message titles and levels (./twirp/serializers.go),
// identify message templates (./twirp/message-templates/*.tmpl),
// and to identify message types in the UI for grouping/filtering etc.
//
// # Args
//
// Args is used to store the required values to render the message from a
// template with a name matching the Key.
//
// As Args often come from user data, ensuring that all Args values are
// bounded is particularly important.
type AnalysisMessage struct {
	BaseModel
	ID AnalysisMessageID

	AnalysisID   *AnalysisID
	RepositoryID RepositoryEID
	DeliveryID   DeliveryID

	Key analysisMessageKey
	// see AfterFind for the code that converts RawArgs into Args
	RawArgs json.RawMessage     `gorm:"column:args"`
	Args    AnalysisMessageArgs `gorm:"-"`
}

type analysisMessageKey string

// Keys for AnalysisMessages
// Add new keys to TestVerifyAnalysisMessageKeys in twirp/serializers_test.go.
// These are stored in the DB, remove with caution
const (
	MessageSarifExecutionUnsuccessful        analysisMessageKey = "sarif-execution-unsuccessful"
	MessageSarifProcessingSoftLimitExceeded  analysisMessageKey = "sarif-processing-soft-limit-exceeded"
	MessageSarifNoAnalyzableCode             analysisMessageKey = "no-analyzable-code"
	MessageSarifCodeQLNotification           analysisMessageKey = "codeql-notification"
	MessageSarifRunsMergeIgnoredUnsuccessful analysisMessageKey = "sarif-runs-merge-ignored-unsuccessful"
	MessageSarifParsingFailed                analysisMessageKey = "sarif-parsing-failed"
	MessageZipInvalidArgs                    analysisMessageKey = "zip-invalid"
	MessageSarifTooBigArgs                   analysisMessageKey = "sarif-too-big"
	MessageZipTooBigArgs                     analysisMessageKey = "zip-too-big"
	MessageSarifNoRuns                       analysisMessageKey = "sarif-no-runs"

	MessageDefaultSetupRejectedUpload analysisMessageKey = "default-setup-rejected-upload"

	MessageSarifSoftLimitResultsPerRun             analysisMessageKey = "sarif-soft-limit-results-per-run"
	MessageSarifSoftLimitThreadFlows               analysisMessageKey = "sarif-soft-limit-thread-flows"
	MessageSarifSoftLimitTagsPerRule               analysisMessageKey = "sarif-soft-limit-tags-per-rule"
	MessageSarifSoftLimitRelatedLocations          analysisMessageKey = "sarif-soft-limit-related-locations"
	MessageSarifSoftLimitExtractedFilesStatus      analysisMessageKey = "sarif-soft-limit-extracted-files-status"
	MessageSarifSoftLimitNotExtractedFilesMessages analysisMessageKey = "sarif-soft-limit-not-extracted-files-messages"
	MessageLogicalAlertsSoftLimitExceeded          analysisMessageKey = "logical-alerts-soft-limit-exceeded"

	MessageSarifHardLimitRelatedLocations analysisMessageKey = "sarif-hard-limit-related-locations"
	MessageSarifHardLimitRuns             analysisMessageKey = "sarif-hard-limit-runs"
	MessageSarifHardLimitThreadFlows      analysisMessageKey = "sarif-hard-limit-thread-flows"
	MessageSarifHardLimitTagsPerRule      analysisMessageKey = "sarif-hard-limit-tags-per-rule"
	MessageSarifHardLimitToolExtensions   analysisMessageKey = "sarif-hard-limit-tool-extensions-per-run"
	MessageSarifHardLimitResultsPerRun    analysisMessageKey = "sarif-hard-limit-results-per-run"
	MessageSarifHardLimitRulesPerRun      analysisMessageKey = "sarif-hard-limit-rules-per-run"
	MessageLogicalAlertsHardLimitExceeded analysisMessageKey = "logical-alerts-hard-limit-exceeded"
)

// AnalysisMessageArgs allows message writers to expose their key to other packages by defining a type that will
// hold the serialized and deserialized arguments in the database.
type AnalysisMessageArgs interface {
	Key() analysisMessageKey
}

type MessageDeclaration interface {
	Key() analysisMessageKey
	Unmarshal(json.RawMessage) (AnalysisMessageArgs, error)
	Title(AnalysisMessageArgs, *Analysis) string
	Level(AnalysisMessageArgs) proto.AnalysisMessageLevel
	// Verify is used by tests to check the declaration is complete
	Verify() error
}

type messageDeclaration[Args AnalysisMessageArgs] struct {
	key   analysisMessageKey
	title func(Args, *Analysis) string
	level func(Args) proto.AnalysisMessageLevel
}

func (decl messageDeclaration[any]) Key() analysisMessageKey {
	return decl.key
}

func (decl messageDeclaration[T]) Unmarshal(data json.RawMessage) (AnalysisMessageArgs, error) {
	return unmarshalAs[T](data)
}

func (decl messageDeclaration[T]) Title(args AnalysisMessageArgs, a *Analysis) string {
	return decl.title(args.(T), a)
}

func (decl messageDeclaration[T]) Level(args AnalysisMessageArgs) proto.AnalysisMessageLevel {
	return decl.level(args.(T))
}

func (decl messageDeclaration[T]) Verify() error {
	if decl.key == analysisMessageKey("") {
		return errors.New("no key set")
	}
	if decl.title == nil {
		return errors.New("no title defined")
	}
	if decl.level == nil {
		return errors.New("no error level set")
	}

	return nil
}

func (decl messageDeclaration[T]) withTitle(title string) messageDeclaration[T] {
	decl.title = func(args T, analysis *Analysis) string {
		return title
	}
	return decl
}

func (decl messageDeclaration[T]) withLevel(level proto.AnalysisMessageLevel) messageDeclaration[T] {
	decl.level = func(args T) proto.AnalysisMessageLevel {
		return level
	}
	return decl
}

func GetAnalysisMessageDecl(key analysisMessageKey) MessageDeclaration {
	switch key {
	case MessageSarifExecutionUnsuccessful:
		return messageDeclaration[SarifExecutionUnsuccessfulArgs]{
			key: MessageSarifExecutionUnsuccessful,
			title: func(args SarifExecutionUnsuccessfulArgs, analysis *Analysis) string {
				if analysis.ToolVersion.Tool.IsCodeQL() {
					return "CodeQL exited with errors"
				} else {
					return fmt.Sprintf("Code scanning tool `%s` exited with errors", analysis.ToolVersion.Tool.CanonicalName)
				}
			},
		}.withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifProcessingSoftLimitExceeded:
		return messageDeclaration[SarifProcessingSoftLimitExceededArgs]{
			key: MessageSarifProcessingSoftLimitExceeded,
		}.withTitle("SARIF document exceeded our internal limits").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifNoAnalyzableCode:
		return messageDeclaration[SarifNoAnalyzableCodeArgs]{
			key: MessageSarifNoAnalyzableCode,
		}.withTitle("Code scanning tool found no code to analyze").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifCodeQLNotification:
		return messageDeclaration[SarifCodeQLNotificationArgs]{
			key: MessageSarifCodeQLNotification,
			title: func(args SarifCodeQLNotificationArgs, _ *Analysis) string {
				return args.ShortDescriptionText
			},
			level: func(args SarifCodeQLNotificationArgs) proto.AnalysisMessageLevel {
				switch args.Level {
				case "error":
					return proto.AnalysisMessageLevel_DANGER
				case "warning":
					return proto.AnalysisMessageLevel_ATTENTION
				case "note":
					return proto.AnalysisMessageLevel_SUCCESS
				case "none":
					return proto.AnalysisMessageLevel_SUCCESS
				default:
					// Default to warning if the level is missing or not one of the known ones
					return proto.AnalysisMessageLevel_ATTENTION
				}
			},
		}
	case MessageSarifRunsMergeIgnoredUnsuccessful:
		return messageDeclaration[SarifRunsMergeIgnoredUnsuccessfulArgs]{
			key: MessageSarifRunsMergeIgnoredUnsuccessful,
		}.withTitle("Some tool invocations failed").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifParsingFailed:
		return messageDeclaration[SarifParsingFailedArgs]{
			key: MessageSarifParsingFailed,
		}.withTitle("SARIF file invalid").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageZipInvalidArgs:
		return messageDeclaration[ZipInvalidArgs]{
			key: MessageZipInvalidArgs,
			title: func(args ZipInvalidArgs, _ *Analysis) string {
				if args.Empty {
					return "SARIF ZIP upload was empty"
				}
				return "SARIF ZIP upload is invalid"
			},
		}.withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifTooBigArgs:
		return messageDeclaration[SarifTooBigArgs]{
			key: MessageSarifTooBigArgs,
		}.withTitle("SARIF upload is too large").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageZipTooBigArgs:
		return messageDeclaration[ZipTooBigArgs]{
			key: MessageZipTooBigArgs,
		}.withTitle("SARIF ZIP upload is too large").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifNoRuns:
		return messageDeclaration[SarifNoRunsArgs]{
			key: MessageSarifNoRuns,
		}.withTitle("SARIF upload does not contain any runs").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageDefaultSetupRejectedUpload:
		return messageDeclaration[DefaultSetupRejectedUploadArgs]{
			key: MessageDefaultSetupRejectedUpload,
		}.withTitle(`Upload with CodeQL results rejected due to "default setup"`).
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifSoftLimitResultsPerRun:
		return messageDeclaration[SarifSoftLimitResultsPerRunArgs]{
			key: MessageSarifSoftLimitResultsPerRun,
		}.withTitle("Analysis SARIF file exceeded alert limits").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifSoftLimitThreadFlows:
		return messageDeclaration[SarifSoftLimitThreadFlowsArgs]{
			key: MessageSarifSoftLimitThreadFlows,
			title: func(args SarifSoftLimitThreadFlowsArgs, _ *Analysis) string {
				if args.AlertCount == 1 {
					return "Alert in SARIF upload exceeded thread flow location limits"
				} else {
					return "Alerts in SARIF upload exceeded thread flow location limits"
				}
			},
		}.withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifSoftLimitTagsPerRule:
		return messageDeclaration[SarifSoftLimitTagsPerRuleArgs]{
			key: MessageSarifSoftLimitTagsPerRule,
		}.withTitle("Rule tags in SARIF file exceed limits").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifSoftLimitRelatedLocations:
		return messageDeclaration[SarifSoftLimitRelatedLocationsPerResultArgs]{
			key: MessageSarifSoftLimitRelatedLocations,
		}.withTitle("Locations for an alert exceeded limits").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	case MessageSarifSoftLimitExtractedFilesStatus:
		return messageDeclaration[SarifSoftLimitExtractedFilesStatusArgs]{
			key: MessageSarifSoftLimitExtractedFilesStatus,
		}.withTitle("Code scanning can not display complete file coverage information").
			withLevel(proto.AnalysisMessageLevel_SUCCESS)
	case MessageSarifSoftLimitNotExtractedFilesMessages:
		return messageDeclaration[SarifSoftLimitNotExtractedFilesMessagesArgs]{
			key: MessageSarifSoftLimitNotExtractedFilesMessages,
		}.withTitle("Diagnostic messages for not analyzed files exceeded limits").
			withLevel(proto.AnalysisMessageLevel_SUCCESS)
	case MessageSarifHardLimitRelatedLocations:
		return messageDeclaration[SarifHardLimitRelatedLocationsPerResultArgs]{
			key: MessageSarifHardLimitRelatedLocations,
		}.withTitle("Analysis SARIF file rejected due to location limit").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitRuns:
		return messageDeclaration[SarifHardLimitRunsArgs]{
			key: MessageSarifHardLimitRuns,
		}.withTitle("Analysis SARIF file rejected due to run limits").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitThreadFlows:
		return messageDeclaration[SarifHardLimitThreadFlowsArgs]{
			key: MessageSarifHardLimitThreadFlows,
			title: func(args SarifHardLimitThreadFlowsArgs, _ *Analysis) string {
				return "Alert(s) in SARIF file exceeded thread flow location limits"
			},
		}.withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitTagsPerRule:
		return messageDeclaration[SarifHardLimitTagsPerRuleArgs]{
			key: MessageSarifHardLimitTagsPerRule,
		}.withTitle("Analysis SARIF file rejected due to rule tag limits").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitToolExtensions:
		return messageDeclaration[SarifHardLimitToolExtensionsArgs]{
			key: MessageSarifHardLimitToolExtensions,
		}.withTitle("Analysis SARIF file rejected due to extension limits").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitResultsPerRun:
		return messageDeclaration[SarifHardLimitResultsPerRunArgs]{
			key: MessageSarifHardLimitResultsPerRun,
		}.withTitle("Analysis SARIF file rejected due to result limits").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageSarifHardLimitRulesPerRun:
		return messageDeclaration[SarifHardLimitRulesPerRunArgs]{
			key: MessageSarifHardLimitRulesPerRun,
		}.withTitle("Analysis SARIF file rejected due to rule limits").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageLogicalAlertsHardLimitExceeded:
		return messageDeclaration[LogicalAlertsHardLimitExceededArgs]{
			key: MessageLogicalAlertsHardLimitExceeded,
		}.withTitle("All analysis uploads blocked due to alert limit").
			withLevel(proto.AnalysisMessageLevel_DANGER)
	case MessageLogicalAlertsSoftLimitExceeded:
		return messageDeclaration[LogicalAlertsSoftLimitExceededArgs]{
			key: MessageLogicalAlertsSoftLimitExceeded,
		}.withTitle("Repository is at risk of exceeding the alert limit").
			withLevel(proto.AnalysisMessageLevel_ATTENTION)
	default:
		panic(fmt.Sprintf("Missing case \"%s\" for analysisMessageKey", key))
	}
}

// WARNING:
// modifying the argument structs may require a corresponding database migration if any of the fields are renamed
// or moved

type SarifExecutionUnsuccessfulArgs struct {
	ExitCode            string `json:"ExitCode"`
	ExitCodeDescription string `json:"ExitCodeDescription"`
}

func (SarifExecutionUnsuccessfulArgs) Key() analysisMessageKey {
	return MessageSarifExecutionUnsuccessful
}

type SarifProcessingSoftLimitExceededArg struct {
	Name    string `json:"Name"`
	Dropped int    `json:"Dropped"`
	Max     int    `json:"Max"`
}

func (SarifProcessingSoftLimitExceededArgs) Key() analysisMessageKey {
	return MessageSarifProcessingSoftLimitExceeded
}

type SarifProcessingSoftLimitExceededArgs struct {
	Limits []SarifProcessingSoftLimitExceededArg `json:"Limits"`
}

type SarifSoftLimitResultsPerRunArgs struct {
	Total int `json:"Total"`
	Limit int `json:"Limit"`
}

func (SarifSoftLimitResultsPerRunArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitResultsPerRun
}

type SarifSoftLimitThreadFlowsArgs struct {
	Limit               int `json:"Limit"`
	AlertCount          int `json:"AlertCount"`
	MaxThreadFlowsCount int `json:"MaxThreadFlowsCount"`
	// This should really be called RulesAboveLimit but this is in the db now...
	ThreadFlowsAboveLimit int      `json:"ThreadFlowsAboveLimit"`
	ExampleRuleSarifIds   []string `json:"ExampleRuleSarifIds"`
}

func (SarifSoftLimitThreadFlowsArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitThreadFlows
}

type SarifSoftLimitTagsPerRuleArgs struct {
	Limit               int      `json:"Limit"`               // The limit value
	ExampleRuleSarifIds []string `json:"ExampleRuleSarifIds"` // Sarif ids of up to 3 rules exceeding the limit.
	MaxRuleTagsCount    int      `json:"MaxRuleTagsCount"`    // The tag count of the rule with the most tags.
	RulesAboveLimit     int      `json:"RulesAboveLimit"`     // The total count of rules exceeding the tag limit
}

func (SarifSoftLimitTagsPerRuleArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitTagsPerRule
}

type SarifSoftLimitRelatedLocationsPerResultArgs struct {
	Limit                    int `json:"Limit"`
	AlertCount               int `json:"AlertCount"`
	MaxRelatedLocationsCount int `json:"MaxRelatedLocationsCount"`
	// This should really be called RulesAboveLimit but this is in the db now...
	RelatedLocationsAboveLimit int      `json:"RelatedLocationsAboveLimit"`
	ExampleRuleSarifIds        []string `json:"ExampleRuleSarifIds"`
}

func (SarifSoftLimitExtractedFilesStatusArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitExtractedFilesStatus
}

type SarifSoftLimitExtractedFilesStatusArgs struct {
	ExtractedStatus bool `json:"ExtractedStatus"`
}

func (SarifHardLimitRelatedLocationsPerResultArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitRelatedLocations
}

type SarifSoftLimitNotExtractedFilesMessagesArgs struct {
	Limit        int `json:"Limit"`
	MessageCount int `json:"MessageCount"`
}

func (SarifSoftLimitNotExtractedFilesMessagesArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitNotExtractedFilesMessages
}

type SarifHardLimitRelatedLocationsPerResultArgs struct {
	Limit                    int `json:"Limit"`
	AlertCount               int `json:"AlertCount"`
	MaxRelatedLocationsCount int `json:"MaxRelatedLocationsCount"`
	// This should really be called RulesAboveLimit but this is in the db now...
	RelatedLocationsAboveLimit int      `json:"RelatedLocationsAboveLimit"`
	ExampleRuleSarifIds        []string `json:"ExampleRuleSarifIds"`
}

func (SarifSoftLimitRelatedLocationsPerResultArgs) Key() analysisMessageKey {
	return MessageSarifSoftLimitRelatedLocations
}

type SarifHardLimitRunsArgs struct {
	RunCount int `json:"RunCount"`
	RunLimit int `json:"RunLimit"`
}

func (SarifHardLimitRunsArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitRuns
}

type SarifHardLimitResultsPerRunArgs struct {
	ResultCount int `json:"ResultCount"`
	Limit       int `json:"Limit"`
}

func (SarifHardLimitResultsPerRunArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitResultsPerRun
}

type SarifHardLimitRulesPerRunArgs struct {
	RuleCount int `json:"RuleCount"`
	Limit     int `json:"Limit"`
}

func (SarifHardLimitRulesPerRunArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitRulesPerRun
}

type SarifHardLimitTagsPerRuleArgs struct {
	Limit               int      `json:"Limit"`               // The limit value
	ExampleRuleSarifIds []string `json:"ExampleRuleSarifIds"` // Sarif ids of up to 3 rules exceeding the limit.
	MaxRuleTagsCount    int      `json:"MaxRuleTagsCount"`    // The tag count of the rule with the most tags.
	RulesAboveLimit     int      `json:"RulesAboveLimit"`     // The total count of rules exceeding the tag limit
}

func (SarifHardLimitTagsPerRuleArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitTagsPerRule
}

type SarifHardLimitThreadFlowsArgs struct {
	Limit               int `json:"Limit"`
	AlertCount          int `json:"AlertCount"`
	MaxThreadFlowsCount int `json:"MaxThreadFlowsCount"`
	// This should really be called RulesAboveLimit but this is in the db now...
	ThreadFlowsAboveLimit int      `json:"ThreadFlowsAboveLimit"`
	ExampleRuleSarifIds   []string `json:"ExampleRuleSarifIds"`
}

func (SarifHardLimitThreadFlowsArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitThreadFlows
}

type SarifHardLimitToolExtensionsArgs struct {
	Limit          int `json:"Limit"`
	ExtensionCount int `json:"ExtensionCount"`
}

func (SarifHardLimitToolExtensionsArgs) Key() analysisMessageKey {
	return MessageSarifHardLimitToolExtensions
}

type SarifNoAnalyzableCodeArgs struct{}

func (SarifNoAnalyzableCodeArgs) Key() analysisMessageKey {
	return MessageSarifNoAnalyzableCode
}

type AnalysisMessageLocation struct {
	FilePath    string `json:"FilePath"`
	StartLine   int    `json:"StartLine"`
	EndLine     int    `json:"EndLine"`
	StartColumn int    `json:"StartColumn"`
	EndColumn   int    `json:"EndColumn"`
}

type SarifCodeQLNotificationArgs struct {
	ShortDescriptionText string                     `json:"ShortDescriptionText"`
	Id                   string                     `json:"Id"`
	MessageText          string                     `json:"MessageText"`
	MessageMarkdown      string                     `json:"MessageMarkdown"`
	Level                string                     `json:"Level"`
	HelpLinks            []string                   `json:"HelpLinks"`
	Locations            []*AnalysisMessageLocation `json:"Locations"`
}

func (SarifCodeQLNotificationArgs) Key() analysisMessageKey {
	return MessageSarifCodeQLNotification
}

type SarifRunsMergeIgnoredUnsuccessfulArgs struct {
	ToolName string `json:"ToolName"`
}

func (SarifRunsMergeIgnoredUnsuccessfulArgs) Key() analysisMessageKey {
	return MessageSarifRunsMergeIgnoredUnsuccessful
}

type SarifParsingFailedArgs struct {
	Error string `json:"Error"`
}

func (SarifParsingFailedArgs) Key() analysisMessageKey {
	return MessageSarifParsingFailed
}

type ZipInvalidArgs struct {
	Empty bool `json:"Empty"`
}

func (ZipInvalidArgs) Key() analysisMessageKey {
	return MessageZipInvalidArgs
}

type SarifTooBigArgs struct {
	Max string `json:"Max"`
}

func (SarifTooBigArgs) Key() analysisMessageKey {
	return MessageSarifTooBigArgs
}

type ZipTooBigArgs struct {
	Max string `json:"Max"`
}

func (ZipTooBigArgs) Key() analysisMessageKey {
	return MessageZipTooBigArgs
}

type SarifNoRunsArgs struct{}

func (SarifNoRunsArgs) Key() analysisMessageKey {
	return MessageSarifNoRuns
}

type DefaultSetupRejectedUploadArgs struct{}

func (DefaultSetupRejectedUploadArgs) Key() analysisMessageKey {
	return MessageDefaultSetupRejectedUpload
}

type LogicalAlertsHardLimitExceededArgs struct {
	Limit int `json:"Limit"`
}

func (LogicalAlertsHardLimitExceededArgs) Key() analysisMessageKey {
	return MessageLogicalAlertsHardLimitExceeded
}

type LogicalAlertsSoftLimitExceededArgs struct {
	Limit     int `json:"Limit"`
	HardLimit int `json:"HardLimit"`
}

func (LogicalAlertsSoftLimitExceededArgs) Key() analysisMessageKey {
	return MessageLogicalAlertsSoftLimitExceeded
}

// AfterFind deserializes RawArgs into the Args field using type information derived from the AnalysisMessage Key
func (a *AnalysisMessage) AfterFind(_ *gorm.DB) (err error) {
	a.Args, err = GetAnalysisMessageDecl(a.Key).Unmarshal(a.RawArgs)
	return err
}

// unmarshalAs deserializes a json.RawMessage into type V
func unmarshalAs[V any](data json.RawMessage) (V, error) {
	var v V
	return v, json.Unmarshal(data, &v)
}
