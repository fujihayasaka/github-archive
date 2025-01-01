package twirp

import (
	"bytes"
	"embed"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"text/template"

	"golang.org/x/exp/maps"

	"golang.org/x/exp/slices"

	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	pb "google.golang.org/protobuf/proto"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
)

func serizalizePullRequestAlerts(prAlerts *ts.PRAlerts, limit uint32) (*proto.PullRequestAlertsResponse, error) {
	newAlertsProto, err := serializeDiffedAlerts(prAlerts.NewAlerts, limit, 0)
	if err != nil {
		return nil, err
	}

	fixedAlertsProto, err := serializeDiffedAlerts(prAlerts.FixedAlerts, limit, 0)
	if err != nil {
		return nil, err
	}

	missingCategories := make(map[string]*proto.MissingCategorySummary)
	for k, a := range prAlerts.MissingCategories {
		missingCategories[k.String()] = &proto.MissingCategorySummary{
			DeliveryOrigin: serializeDeliveryOrigin(a.DeliveryOrigin),
			WorkflowPath:   a.WorkflowPath.Bytes(),
		}
	}

	newCategories := make(map[string]*proto.NewCategorySummary)
	for k, v := range prAlerts.NewCategories {
		newCategories[k.String()] = &proto.NewCategorySummary{
			AlertCount: v,
		}
	}

	out := &proto.PullRequestAlertsResponse{
		NewCount:          uint64(len(prAlerts.NewAlerts)),
		NewAlerts:         newAlertsProto,
		FixedCount:        uint64(len(prAlerts.FixedAlerts)),
		FixedAlerts:       fixedAlertsProto,
		MissingCategories: missingCategories,
		NewCategories:     newCategories,
		LatestUploadTime:  serializeTime(prAlerts.LatestUploadTime),
	}

	err = extendPullRequestAlertsResponseWithSeverityCounts(out, prAlerts.NewAlerts)
	if err != nil {
		return nil, err
	}

	return out, nil
}

func serializeDiffedAlerts(alerts []*ts.LogicalAlert, limit uint32, offset uint32) ([]*proto.DiffedAlert, error) {
	var result []*proto.DiffedAlert
	alertCount := uint32(len(alerts))
	if offset > alertCount {
		return result, nil
	}
	// Alerts are already sorted, so no need to do that here
	end := offset + limit
	if end > alertCount {
		end = alertCount
	}
	filteredAlerts := alerts[offset:end]

	for _, la := range filteredAlerts {
		rule := la.Rule
		protoSeverity := proto.RuleSeverity(proto.RuleSeverity_value[strings.ToUpper(la.SeverityLevel.String())]) // TODO: replace this string conversion
		a := &proto.DiffedAlert{
			MessageText:          la.Message,
			MessageMarkdown:      la.MessageMarkdown,
			RuleShortDescription: rule.ShortDescription,
			RuleSeverity:         protoSeverity,
			SecuritySeverity:     la.SecuritySeverityLevel(),
			Number:               la.Number,
			Location:             serializeLocation(la.FilePath, la.Region),
			RuleSarifIdentifier:  rule.SarifIdentifier,
		}
		result = append(result, a)
	}
	return result, nil
}

func serializeCodeFlowResult(c []ts.CodeFlows) []*proto.CodePath {
	codePaths := make([]*proto.CodePath, 0, len(c))

	for _, codeFlow := range c {
		codePath := &proto.CodePath{
			Steps: make([]*proto.CodePathStep, 0, len(codeFlow)),
		}
		for _, step := range codeFlow {
			message := ""
			if step.Message != nil {
				message = *step.Message
			}
			codePath.Steps = append(codePath.Steps, &proto.CodePathStep{
				Location: serializeLocation(step.FilePath, step.Region),
				Message:  message,
			})
		}
		codePaths = append(codePaths, codePath)
	}

	return codePaths
}

func serializeAnalysisKey(a *ts.Analysis) *proto.AnalysisKey {
	if a == nil || a.ID == 0 {
		// zero value
		return nil
	}
	var tool string
	if a.Tool != nil {
		tool = a.Tool.CanonicalName.String()
	}
	environment := "{}"
	if a.Environment != nil {
		environment = a.Environment.String()
	}
	return &proto.AnalysisKey{
		Id:          uint64(a.ID),
		AnalysisKey: a.AnalysisKey.String(),
		Tool:        tool,
		Environment: environment,
		CommitOid:   a.CommitOid.String(),
		Category:    a.Category.String(),
	}
}

func serializeAnalysis(a ts.Analysis, processErrors []*ts.ProcessError, isDeletable bool) *proto.Analysis {
	// call Error() on each ProcessError and join the results with newlines
	errs := strings.Join(transforms.Map(processErrors, (*ts.ProcessError).Error), "\n")
	if a.Failed && errs == "" {
		errs = "Unknown Error"
	}
	out := &proto.Analysis{
		Id:              uint64(a.ID),
		RefNameBytes:    a.Ref,
		AnalysisKey:     a.AnalysisKey.String(),
		Environment:     a.Environment.String(),
		CreatedAt:       serializeTime(&a.CreatedAt),
		CommitOid:       a.CommitOid.String(),
		BuildStartedAt:  serializeTime(a.BuildStartedAt),
		SarifId:         a.SarifID.String(),
		UploadStartedAt: serializeTime(a.UploadStartedAt),
		ResultsCount:    uint32(a.ResultsCount),
		RulesCount:      uint32(a.RulesCount),
		ToolDescription: serializeToolDescription(a.Tool, a.ToolVersion),
		MostRecent:      a.MostRecent,
		Deletable:       isDeletable,
		Category:        a.Category.String(),
		WorkflowRunId:   uint64(a.WorkflowRunID),
		Status:          a.Status(),
		Errors:          errs,
		IsOutdated:      a.IsOutdated,
		DeliveryOrigin:  serializeDeliveryOrigin(a.DeliveryOrigin),
		WorkflowPath:    a.WorkflowPath.Bytes(),
	}

	if a.ProcessWarning != nil {
		out.ProcessWarning = *a.ProcessWarning
	}

	return out
}

func serializeRelatedLocationsResult(r []*ts.RelatedLocation) []*proto.RelatedLocation {
	relatedLocations := make([]*proto.RelatedLocation, 0, len(r))

	for _, rl := range r {
		relatedLocation := &proto.RelatedLocation{
			CreatedAt:        serializeTime(&rl.CreatedAt),
			UpdatedAt:        serializeTime(&rl.UpdatedAt),
			Message:          rl.Message,
			ReplacementIndex: rl.ReplacementIndex,
			Location:         serializeLocation(rl.FilePath, rl.Region),
		}
		relatedLocations = append(relatedLocations, relatedLocation)
	}
	return relatedLocations
}

func serializeAlertInPullRequest(pa *ts.PhysicalAlert, introducedAt, fixedAt *sqltime.Time) *proto.AlertInPullRequest {
	la := pa.LogicalAlert
	return &proto.AlertInPullRequest{
		AlertNumber:         la.Number,
		AnalysisId:          uint64(pa.Analysis.ID),
		CreatedAt:           serializeTime(introducedAt), // When it was first introduced in the PR
		UpdatedAt:           serializeTime(&pa.UpdatedAt),
		Fixed:               pa.IsFixed,
		Resolution:          SerializeResolution(la.Resolution),
		Severity:            pa.SecuritySeverityLevel(),
		RefNameBytes:        pa.Analysis.Ref,
		Tool:                pa.Analysis.Tool.CanonicalName.String(),
		RuleSarifIdentifier: la.SarifIdentifier,
		ResolvedAt:          serializeTime(la.ResolvedAt),
		FixedAt:             serializeTime(fixedAt),
	}
}

func serializeAlertInstance(pa *ts.PhysicalAlert, la *ts.LogicalAlert) *proto.AlertInstance {
	var commit ts.Sha
	if pa.Analysis != nil {
		commit = pa.Analysis.CommitOid
	}
	if pa.IsFixed && pa.LastSeenAnalysis != nil {
		commit = pa.LastSeenAnalysis.CommitOid
	}
	classification := serializeClassification(la.FileClassification)
	return &proto.AlertInstance{
		CreatedAt:             serializeTime(&pa.CreatedAt),
		CommitOid:             commit.String(),
		RefNameBytes:          pa.Analysis.Ref,
		Location:              serializeLocation(la.FilePath, pa.Region),
		IsFixed:               pa.IsFixed,
		HasFileClassification: len(la.FileClassification) > 0,
		AnalysisKey:           serializeAnalysisKey(pa.Analysis),
		Classification:        classification,
		MessageText:           la.Message,
		IsOutdated:            pa.Analysis.IsOutdated,
	}
}

func serializeClassification(cs []string) []string {
	// Sort and remove duplicates from the classification list.
	if len(cs) == 0 {
		return nil
	}
	out := transforms.Unique(cs)

	sort.Strings(out)

	return out
}

func serializeResult(la ts.LogicalAlert) (*proto.Result, error) {
	pa, err := la.Canonical()
	if err != nil {
		return nil, err
	}
	tsRule := la.Rule
	createdAt := serializeTime(&la.CreatedAt) // TODO: this is the db create time, should it be commit time or similar?
	var resolverID uint32
	if la.ResolverID != nil {
		resolverID = uint32(*la.ResolverID)
	}

	// Pick the tool version from the first physical alert provided
	tool := serializeToolDescription(tsRule.Tool, pa.Analysis.ToolVersion)

	if la.IsFixed == nil {
		return nil, errors.New("logical alert loaded without including is_fixed column")
	}

	rule, err := serializeRule(tsRule)
	if err != nil {
		return nil, err
	}

	// override the rule's severity with the result severity
	rule.Severity = serializeRuleSeverity(la.SeverityLevel)

	updatedAt := &la.UpdatedAt
	// transparently replace updated_at with last_state_change_at calculated field.
	if la.LastStateChangeAt != nil {
		updatedAt = la.LastStateChangeAt
	}

	result := &proto.Result{
		MessageText:        la.Message,
		MessageMarkdown:    la.MessageMarkdown,
		RuleSeverity:       serializeRuleSeverity(la.SeverityLevel),
		SecuritySeverity:   la.SecuritySeverityLevel(),
		CreatedAt:          createdAt,
		Resolution:         SerializeResolution(la.Resolution),
		ResolverId:         resolverID,
		ResolvedAt:         serializeTime(la.ResolvedAt),
		ResolutionNote:     la.ResolutionNote.String(),
		Number:             la.Number,
		MostRecentInstance: serializeAlertInstance(la.PhysicalAlerts[0], &la),
		Tool:               tool,
		Guid:               la.GUID,
		IsFixed:            *la.IsFixed,
		Rule:               rule,
		FixedAt:            serializeTime(la.GetFixedAt()),
		UpdatedAt:          serializeTime(updatedAt),
	}

	return result, nil
}

func serializeTime(time *sqltime.Time) *timestamppb.Timestamp {
	if time == nil {
		return nil
	}

	return timestamppb.New(time.Time)
}

func serializeTimelineEvents(events []*ts.TimelineEvent) []*proto.TimelineEvent {
	timelineEvents := make([]*proto.TimelineEvent, 0, len(events))

	for _, event := range events {
		var startLine uint32
		if event.StartLine == 0 {
			startLine = 1
		} else {
			startLine = event.StartLine
		}

		var toolVersion string
		if event.ToolVersion_ != nil {
			toolVersion = event.ToolVersion_.GetVersion()
		}

		protobufEvent := &proto.TimelineEvent{
			Id:             uint64(event.ID),
			LogicalAlertId: uint64(event.LogicalAlertID),
			Type:           serializeTimelineEventType(event.EventType),
			Message:        "",
			Timestamp:      serializeTime(&event.EventTimestamp),
			CommitOid:      event.CommitOid.String(),
			RefNameBytes:   []byte(event.Ref),
			Resolution:     SerializeResolution(event.Resolution),
			ResolutionNote: event.ResolutionNote.String(),
			FilePath:       event.FilePath,
			StartLine:      startLine,
			ToolVersion:    toolVersion,
			Environment:    serializeEnvironment(event.Environment),
			WorkflowRunId:  uint64(event.WorkflowRunID),
			Category:       event.Category,
		}

		if event.UserID != nil {
			protobufEvent.UserId = uint32(*event.UserID)
		}

		timelineEvents = append(timelineEvents, protobufEvent)
	}

	return timelineEvents
}

func serializeEnvironment(environment ts.AnalysisEnv) []*proto.EnvironmentData {
	environments := make([]*proto.EnvironmentData, 0, len(environment))

	for key, value := range environment {
		environmentData := &proto.EnvironmentData{
			Key:   key,
			Value: value,
		}

		environments = append(environments, environmentData)
	}

	return environments
}

func serializeTimelineEventType(modelEventType ts.TimelineEventType) proto.TimelineEventType {
	var eventType proto.TimelineEventType
	switch modelEventType {
	case ts.TimelineEventTypeAlertAppearedInBranch:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_APPEARED_IN_BRANCH
	case ts.TimelineEventTypeAlertClosedBecameFixed:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_CLOSED_BECAME_FIXED
	case ts.TimelineEventTypeAlertClosedBecameOutdated:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_CLOSED_BECAME_OUTDATED
	case ts.TimelineEventTypeAlertResolvedByUser:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_CLOSED_BY_USER
	case ts.TimelineEventTypeAlertCreated:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_CREATED
	case ts.TimelineEventTypeAlertReappeared:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_REAPPEARED
	case ts.TimelineEventTypeAlertReopenedByUser:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_REOPENED_BY_USER
	case ts.TimelineEventTypeAlertDeletedByUser:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_ALERT_DELETED_BY_USER
	case ts.TimelineEventTypeUnknown:
		eventType = proto.TimelineEventType_TIMELINE_EVENT_TYPE_UNKNOWN
	}

	return eventType
}

func SerializeResolution(modelResolution ts.AlertResolution) proto.ResultResolution {
	switch modelResolution {
	case ts.AlertResolutionNone:
		return proto.ResultResolution_NO_RESOLUTION
	case ts.AlertResolutionFalsePositive:
		return proto.ResultResolution_FALSE_POSITIVE
	case ts.AlertResolutionWontFix:
		return proto.ResultResolution_WONT_FIX
	case ts.AlertResolutionUsedInTests:
		return proto.ResultResolution_USED_IN_TESTS
	default:
		return proto.ResultResolution_NO_RESOLUTION
	}
}

func serializeRuleSeverity(severity ts.SeverityLevel) proto.RuleSeverity {
	switch severity {
	case ts.SeverityLevelError:
		return proto.RuleSeverity_ERROR
	case ts.SeverityLevelWarning:
		return proto.RuleSeverity_WARNING
	case ts.SeverityLevelNote:
		return proto.RuleSeverity_NOTE
	case ts.SeverityLevelNone:
		return proto.RuleSeverity_NONE
	}
	// our linter should ensure this is not possible and the above switch statement is exhaustive
	panic(errors.Errorf("unknown severity %v", severity))
}

func serializeRule(rule *ts.Rule) (*proto.Rule, error) {
	tags, err := rule.GetTags()
	if err != nil {
		return nil, err
	}
	sort.Strings(tags)

	return &proto.Rule{
		SarifIdentifier:  rule.SarifIdentifier,
		ShortDescription: rule.ShortDescription,
		Tags:             tags,
		Name:             rule.Name,
		Severity:         serializeRuleSeverity(rule.SeverityLevel),
		FullDescription:  rule.FullDescription,
		Help:             rule.Help,
		QueryUri:         rule.QueryURI,
		HelpUri:          rule.HelpURI,
	}, nil
}

func serializeRules(tsRules []ts.Rule) ([]*proto.Rule, error) {
	rules := make([]*proto.Rule, 0, len(tsRules))

	for _, tsRule := range tsRules {
		rule, err := serializeRule(&tsRule)
		if err != nil {
			return nil, err
		}
		rules = append(rules, rule)
	}

	sort.Slice(rules, func(i, j int) bool {
		return rules[i].SarifIdentifier < rules[j].SarifIdentifier
	})

	return rules, nil
}

func serializeLocation(filePath string, region ts.Region) *proto.Location {
	// escape any NULL bytes in the filePath. NULL bytes cause various issues on the Ruby side, including
	// exceptions in File.dirname and anything calling out to GitRPCd
	filePath = strings.ReplaceAll(filePath, "\x00", `\x00`)
	var location proto.Location
	if region.IsWholeFile() {
		// If a region has all-zero fields it means the region should be the entire file.
		// This is a bit tricky to display neatly in the UI so instead we show the region as just being the first line of the file.
		location = proto.Location{
			FilePath:    filePath,
			StartLine:   1,
			EndLine:     1,
			StartColumn: 1,
			EndColumn:   1,
		}
	} else {
		location = proto.Location{
			FilePath:    filePath,
			StartLine:   region.StartLine,
			EndLine:     region.EndLine,
			StartColumn: region.StartColumn,
			EndColumn:   region.EndColumn,
		}
	}
	return &location
}

func serializeToolDescription(t *ts.Tool, tv *ts.ToolVersion) *proto.ToolDescription {
	toolGUID := ""
	if !t.IsInternalGUID {
		toolGUID = t.GUID
	}
	tool := &proto.ToolDescription{
		Name:    t.CanonicalName.String(),
		Guid:    toolGUID,
		Version: tv.GetVersion(),
	}

	return tool
}

func serializeCounters(counts map[ts.ToolName]uint64) []*proto.ToolAlertCount {
	var counters []*proto.ToolAlertCount
	for canonicalName, open := range counts {
		counters = append(counters, &proto.ToolAlertCount{
			ToolName:  canonicalName.String(),
			OpenCount: open,
		})
	}
	sort.Slice(counters, func(i, j int) bool {
		if counters[i].ToolName < counters[j].ToolName {
			return true
		}
		if counters[i].ToolName > counters[j].ToolName {
			return false
		}
		return counters[i].OpenCount < counters[j].OpenCount
	})
	return counters
}

// GetMarshaledResult returns a marshalled versions of proto.Result, so it can be reused in other schemas
// Currently, we only rely on this for the serialization of hydro.AlertEvent (since we want both schemas to return the same information)
func GetMarshaledResult(la ts.LogicalAlert) ([]byte, error) {
	result, err := serializeResult(la)
	if err != nil {
		return nil, err
	}
	return pb.Marshal(result)
}

// serializeToolDescriptions converts a list of tools to a list of tool description
// objects, ready to return in a TWIRP response.
func serializeToolDescriptions(tools []ts.Tool) []*proto.ToolDescription {
	names := make([]*proto.ToolDescription, 0, len(tools))

	sort.Slice(tools, func(i, j int) bool {
		return tools[i].ID < tools[j].ID
	})

	for _, t := range tools {
		// TODO: should we be including a version here?
		names = append(names, &proto.ToolDescription{
			Name: t.CanonicalName.String(),
			Guid: t.GUID,
		})
	}

	return names
}

//go:embed message-templates
var messages embed.FS
var templates = func() *template.Template {
	t := template.New("start_name")
	t.Funcs(template.FuncMap{
		"subtract": func(i, j int) int {
			return i - j
		},
	})
	return template.Must(t.ParseFS(messages, "message-templates/*.tmpl"))
}()

// serializeAnalysisMessageLevel determines the level for a serialized AnalysisMessage
func serializeAnalysisMessageLevel(args ts.AnalysisMessageArgs) proto.AnalysisMessageLevel {
	return ts.GetAnalysisMessageDecl(args.Key()).Level(args)
}

// serializeAnalysisMessageTitle determines the title for a serialized AnalysisMessage
func serializeAnalysisMessageTitle(args ts.AnalysisMessageArgs, analysis *ts.Analysis) string {
	return ts.GetAnalysisMessageDecl(args.Key()).Title(args, analysis)
}

func serializeAnalysisMessageKey(args ts.AnalysisMessageArgs) string {
	if args.Key() == ts.MessageSarifCodeQLNotification {
		return "codeql/" + args.(ts.SarifCodeQLNotificationArgs).Id
	}
	return string(args.Key())
}

func serializeAnalysisMessageHelpLinks(args ts.AnalysisMessageArgs) []string {
	if args.Key() == ts.MessageSarifCodeQLNotification {
		return args.(ts.SarifCodeQLNotificationArgs).HelpLinks
	} else {
		return []string{}
	}
}

// defaultErrorMessage returns a default error message for use if there is no associated Key
func defaultErrorMessage(msg string) *proto.AnalysisMessage {
	return &proto.AnalysisMessage{
		Title:   msg,
		Message: "We are unable to provide more information about this error.",
		Level:   proto.AnalysisMessageLevel_DANGER,
		Key:     "default-error",
	}
}

type analysisMessageContext struct {
	Args     ts.AnalysisMessageArgs
	Analysis *ts.Analysis
}

// serializeAnalysisMessage serializes a ts.AnalysisMessage and returns its proto equivalent
func serializeAnalysisMessage(a *ts.Analysis, m *ts.AnalysisMessage) (*proto.AnalysisMessage, error) {
	if m.Args == nil {
		return nil, errors.New("args was nil")
	}

	key := m.Args.Key()
	var message string
	if key == ts.MessageSarifCodeQLNotification {
		// CodeQL notifications come with a markdown and a text field.
		// At the moment we expect just to use the markdown field.
		// The text field is used as fallback but the way we do it is not good since it will
		// be interpreted as markdown by the monolith.
		// We probably have to add proper support for the text field + help links at some point,
		// in which case we'll have to return both to the monolith for rendering
		// but that is yet to be confirmed, see https://github.com/github/code-scanning/issues/8561
		markdown := m.Args.(ts.SarifCodeQLNotificationArgs).MessageMarkdown
		if markdown != "" {
			message = m.Args.(ts.SarifCodeQLNotificationArgs).MessageMarkdown
		} else {
			message = m.Args.(ts.SarifCodeQLNotificationArgs).MessageText
		}

	} else {
		// all other messages we render with a template
		var buf bytes.Buffer
		tmplName := fmt.Sprintf("%s.tmpl", key)
		err := templates.ExecuteTemplate(&buf, tmplName, analysisMessageContext{Args: m.Args, Analysis: a})
		if err != nil {
			return nil, err
		}
		message = buf.String()
	}

	msg := &proto.AnalysisMessage{
		Title:       serializeAnalysisMessageTitle(m.Args, a),
		Message:     message,
		Level:       serializeAnalysisMessageLevel(m.Args),
		Key:         serializeAnalysisMessageKey(m.Args),
		HelpLinks:   serializeAnalysisMessageHelpLinks(m.Args),
		HasAnalysis: m.AnalysisID != nil,
	}

	if notificationsArgs, ok := m.Args.(ts.SarifCodeQLNotificationArgs); ok {
		msg.Locations = transforms.Map(notificationsArgs.Locations, func(loc *ts.AnalysisMessageLocation) *proto.Location {
			tsRegion := ts.Region{
				StartLine:   uint32(loc.StartLine),
				StartColumn: uint32(loc.StartColumn),
				EndLine:     uint32(loc.EndLine),
				EndColumn:   uint32(loc.EndColumn),
			}
			return serializeLocation(loc.FilePath, tsRegion)
		})
	}

	return msg, nil
}

func serializeAnalysisMessages(analysis *ts.Analysis) []*proto.AnalysisMessage {
	return transforms.FilterMap(analysis.AnalysisMessages, func(m *ts.AnalysisMessage) (*proto.AnalysisMessage, bool) {
		if m == nil {
			return nil, false
		}
		// originally we reported all the limit messages in one error
		// on GHES this is confusing because the MetricResults limit has an override that sets it to zero
		// we should hide these messages - they will be replaced by a better limit message when the next
		// analysis runs.
		if m.Key == ts.MessageSarifProcessingSoftLimitExceeded {
			return nil, false
		}
		msg, err := serializeAnalysisMessage(analysis, m)
		if err != nil {
			return defaultErrorMessage("Something went wrong with code scanning!"), true
		}

		return msg, true
	})
}

func serializeRuleOrigin(tv *ts.ToolVersion) *proto.RuleOrigin {
	name := tv.Name
	if renamedTool, ok := ts.CanonicalToolRenames[name]; ok {
		name = renamedTool
	}
	return &proto.RuleOrigin{
		Name:    name.String(),
		Version: tv.GetVersion(),
	}
}

func serializeExtractedFiles(extracted, notExtracted ts.FileSet, toolErrors map[string]string) []*proto.ExtractedFile {
	var out []*proto.ExtractedFile

	out = append(out, transforms.Map(maps.Keys(extracted), func(path string) *proto.ExtractedFile {
		return &proto.ExtractedFile{
			Path:    []byte(path),
			Success: true,
			Message: nil,
		}
	})...)

	out = append(out, transforms.Map(maps.Keys(notExtracted), func(path string) *proto.ExtractedFile {
		return &proto.ExtractedFile{
			Path:    []byte(path),
			Success: false,
			Message: []byte(toolErrors[path]),
		}
	})...)

	return out
}

func serializeExtractedLanguageFiles(extractedFiles *ts.AnalysisExtractedFiles, toolErrors map[string]string) map[string]*proto.ExtractedLanguageFiles {
	if extractedFiles == nil {
		return nil
	}

	out := make(map[string]*proto.ExtractedLanguageFiles)
	for language, fs := range extractedFiles.FilesExtracted {
		out[language] = &proto.ExtractedLanguageFiles{
			Files: serializeExtractedFiles(fs, extractedFiles.FilesNotExtracted[language], toolErrors),
		}
	}
	return out
}

func serializeExtractedCategoryFiles(analyses []*ts.Analysis, toolErrors map[string]string) map[string]*proto.ExtractedCategoryFiles {
	out := make(map[string]*proto.ExtractedCategoryFiles)
	for _, analysis := range analyses {
		out[analysis.Category.String()] = &proto.ExtractedCategoryFiles{
			Languages: serializeExtractedLanguageFiles(analysis.AnalysisExtractedFiles, toolErrors),
		}
	}
	return out
}

func serializeExtensionsUsed(analysis *ts.LatestAnalysis, counts []*ts.LatestAnalysisAnalysisRule) []*proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins {
	toolVersions := transforms.IndexBy(analysis.AnalysisToolVersions, func(atv *ts.AnalysisToolVersion) ts.ToolVersionID { return atv.ToolVersionID })

	out := make([]*proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins, 0, len(analysis.AnalysisToolVersions))
	countGroups := transforms.GroupBy(counts, func(ar *ts.LatestAnalysisAnalysisRule) ts.ToolVersionID { return ar.DefiningToolVersionID })
	keys := maps.Keys(countGroups)
	slices.Sort(keys)
	for _, tvID := range keys {
		group := countGroups[tvID]
		atv, ok := toolVersions[tvID]
		toolVersion := &ts.ToolVersion{Name: "N/A"}
		if ok {
			toolVersion = atv.ToolVersion
		}
		slices.SortFunc(group, func(a, b *ts.LatestAnalysisAnalysisRule) int {
			return strings.Compare(a.SarifIdentifier, b.SarifIdentifier)
		})
		out = append(out, &proto.ToolStatusRulesResponse_CategoryRules_RuleOrigins{
			Origin: serializeRuleOrigin(toolVersion),
			Rules: transforms.Map(group, func(r *ts.LatestAnalysisAnalysisRule) *proto.ToolStatusRulesResponse_CategoryRules_Rule {
				return &proto.ToolStatusRulesResponse_CategoryRules_Rule{
					SarifIdentifier: r.SarifIdentifier,
					Results:         r.Results,
				}
			}),
		})
	}
	return out
}

func serializeToolStatusCategoryRules(analysis *ts.LatestAnalysis, counts []*ts.LatestAnalysisAnalysisRule) *proto.ToolStatusRulesResponse_CategoryRules {
	indexed := transforms.GroupBy(counts, func(c *ts.LatestAnalysisAnalysisRule) ts.AnalysisID {
		return c.AnalysisID
	})
	return &proto.ToolStatusRulesResponse_CategoryRules{
		Origins: serializeExtensionsUsed(analysis, indexed[analysis.ID]),
	}
}

func serializeQuerySuiteType(suiteType ts.AnalysisQuerySuiteType) proto.CategoryStatus_QuerySuite_Type {
	switch suiteType {
	case ts.AnalysisQuerySuiteTypeLocalQuery:
		return proto.CategoryStatus_QuerySuite_QUERY_SUITE_LOCAL_QUERY
	case ts.AnalysisQuerySuiteTypeBuiltinSuite:
		return proto.CategoryStatus_QuerySuite_QUERY_SUITE_BUILTIN_SUITE
	case ts.AnalysisQuerySuiteTypeExternalRepo:
		return proto.CategoryStatus_QuerySuite_QUERY_SUITE_EXTERNAL_REPOSITORY
	case ts.AnalysisQuerySuiteTypeUnknown:
		return proto.CategoryStatus_QuerySuite_QUERY_SUITE_UNKNOWN
	default:
		return proto.CategoryStatus_QuerySuite_QUERY_SUITE_UNKNOWN
	}
}

func serializeQuerySuites(suite *ts.AnalysisQuerySuite) *proto.CategoryStatus_QuerySuite {
	return &proto.CategoryStatus_QuerySuite{
		Type: serializeQuerySuiteType(suite.Type),
		Uses: suite.Uses,
	}
}

func serializeCategoryStatus(a *ts.LatestAnalysis) *proto.CategoryStatus {
	return &proto.CategoryStatus{
		WorkflowRunId:  uint64(a.WorkflowRunID),
		AnalysisStatus: a.Status(),
		CommitOid:      a.CommitOid.String(),
		UpdatedAt:      serializeTime(&a.CreatedAt),
		Category:       a.Category.String(),
		ToolVersion:    a.ToolVersion.GetVersion(),
		Extensions: transforms.FilterMap(a.AnalysisToolVersions, func(atv *ts.AnalysisToolVersion) (*proto.RuleOrigin, bool) {
			return serializeRuleOrigin(atv.ToolVersion), atv.ToolVersionID != a.ToolVersionID
		}),
		Messages:               serializeAnalysisMessages(&a.Analysis),
		CreatedAt:              serializeTime(a.MinCreatedAt),
		AnalysisId:             uint64(a.ID),
		IsOutdated:             a.IsOutdated,
		DefaultQueriesDisabled: a.DefaultQueriesDisabled != nil && *a.DefaultQueriesDisabled,
		QuerySuites:            transforms.Map(a.AnalysisQuerySuites, serializeQuerySuites),
		HasMostRecent:          a.HasMostRecent,
		ConfigurationHash:      a.ConfigurationHashBytes,
		ConfigurationGroup: &proto.ConfigurationGroup{
			DeliveryOrigin: serializeDeliveryOrigin(a.DeliveryOrigin),
			WorkflowPath:   a.WorkflowPath.Bytes(),
		},
	}
}

// getToolStatusExtractedMap returns a total ToolStatusExtracted and map of languages to ToolStatusExtracted
// where the map of string to ToolStatusExtracted object contains information about extracted files
// and total files scanned per language.
func getToolStatusExtractedMap(statuses []*ts.AnalysisExtractedFiles) (total *proto.ToolStatusExtracted, languages map[string]*proto.ToolStatusExtracted) {
	extracted, notExtracted := getExtractedAndNotExtractedToolStatusFiles(statuses)
	extractedFileSet, totalFileSet := getExtractedAndBaselineFileSet(extracted, notExtracted)
	total = &proto.ToolStatusExtracted{
		Extracted: uint64(len(extractedFileSet)),
		Total:     uint64(len(totalFileSet)),
	}
	languages = buildToolStatusExtractedMap(extracted, notExtracted)
	return
}

// buildToolStatusExtractedMap returns a map of language to ToolStatusExtracted for getToolStatusExtractedMap.
func buildToolStatusExtractedMap(extracted ts.ToolStatusFiles, notExtracted ts.ToolStatusFiles) map[string]*proto.ToolStatusExtracted {
	// build the result
	res := make(map[string]*proto.ToolStatusExtracted)
	for lang, fs := range extracted {
		if notExtracted == nil {
			res[lang] = &proto.ToolStatusExtracted{
				Extracted: uint64(len(fs)),
			}
			continue
		}
		if ne, ok := notExtracted[lang]; ok {
			if ne == nil {
				res[lang] = &proto.ToolStatusExtracted{
					Extracted: uint64(len(fs)),
				}
				continue
			}
			found := extracted[lang]
			res[lang] = &proto.ToolStatusExtracted{
				Extracted: uint64(len(fs)),
				Total:     uint64(len(found)) + uint64(len(ne.Diff(found))),
			}
		}
	}

	return res
}

// getExtractedAndNotExtractedToolStatusFiles returns two maps, the first of the files that were extracted and
// second of the files that were not extracted
//
// Note that at this stage, we are simply merging the results of all the analyses together, so there will be some
// entries in `notExtracted` that are also in `extracted`.
func getExtractedAndNotExtractedToolStatusFiles(statuses []*ts.AnalysisExtractedFiles) (ts.ToolStatusFiles, ts.ToolStatusFiles) {
	var extracted ts.ToolStatusFiles
	var notExtracted ts.ToolStatusFiles
	for _, status := range statuses {
		if status == nil {
			continue
		}

		extracted = mergeToolStatusFiles(status.FilesExtracted, extracted)
		notExtracted = mergeToolStatusFiles(status.FilesNotExtracted, notExtracted)
	}
	return normalizeToolStatusFiles(extracted, notExtracted)
}

// getExtractedAndBaselineFileSet returns two FileSets, the first of the files that were extracted
// and second of the files that are all the files in baseline (extracted and not extracted).
func getExtractedAndBaselineFileSet(extracted ts.ToolStatusFiles, notExtracted ts.ToolStatusFiles) (ts.FileSet, ts.FileSet) {
	extractedFileSet := make(ts.FileSet)
	for _, fs := range extracted {
		extractedFileSet = extractedFileSet.Union(fs)
	}

	if notExtracted == nil {
		return extractedFileSet, nil
	}

	totalFileSet := make(ts.FileSet)
	for f := range extractedFileSet {
		totalFileSet[f] = struct{}{}
	}
	for _, fs := range notExtracted {
		totalFileSet = totalFileSet.Union(fs)
	}
	return extractedFileSet, totalFileSet
}

// See normalizeToolStatusFiles
var languageQueryIdToDisplayNameMap = map[string]string{
	"cpp":   "C/C++",
	"cs":    "C#",
	"go":    "Go",
	"java":  "Java/Kotlin",
	"js":    "JavaScript/TypeScript",
	"py":    "Python",
	"ql":    "QL",
	"rb":    "Ruby",
	"swift": "Swift",
}

// See normalizeToolStatusFiles
var languageQueryIdToSublanguagesMap = map[string][]string{
	"cpp":  {"C", "C++"},
	"java": {"Java", "Kotlin"},
	"js":   {"JavaScript", "TypeScript"},
}

// mergeToolStatusFiles merges two ToolStatusFiles together, returning a new ToolStatusFiles.
func mergeToolStatusFiles(tsf ts.ToolStatusFiles, merge ts.ToolStatusFiles) ts.ToolStatusFiles {
	if tsf == nil {
		return merge
	}

	out := ts.ToolStatusFiles{}
	for lang, fs := range tsf {
		out[lang] = fs.Union(out[lang])
	}
	for lang, fs := range merge {
		out[lang] = fs.Union(out[lang])
	}
	return out
}

// normalizeToolStatusFiles normalizes a ToolStatusFiles map to handle the result of combining
// configurations with and without sub-language file coverage information.
//
// Specifically, when any language has file coverage information for both its sub-languages and
// its parent language (this can happen for complex setups with multiple analysis configurations),
// we gracefully degrade to reporting the parent language instead of the sub-language. This prevents
// situations where files are double-counted.
func normalizeToolStatusFiles(extracted ts.ToolStatusFiles, notExtracted ts.ToolStatusFiles) (extractedNormalized ts.ToolStatusFiles, notExtractedNormalized ts.ToolStatusFiles) {
	allLangs := map[string]struct{}{}
	for lang := range extracted {
		allLangs[lang] = struct{}{}
	}
	for lang := range notExtracted {
		allLangs[lang] = struct{}{}
	}

	// Maps disabled sublanguages to their parent language
	disabledSublanguages := map[string]string{}

	for lang := range allLangs {
		if sublanguages, ok := languageQueryIdToSublanguagesMap[lang]; ok {
			name := lang
			if displayName, ok := languageQueryIdToDisplayNameMap[lang]; ok {
				name = displayName
			}
			for _, sublang := range sublanguages {
				if _, ok := extracted[sublang]; ok {
					disabledSublanguages[sublang] = name
				}
				if _, ok := notExtracted[sublang]; ok {
					disabledSublanguages[sublang] = name
				}
			}
		}
	}

	return normalizeSublanguages(extracted, disabledSublanguages), normalizeSublanguages(notExtracted, disabledSublanguages)
}

func normalizeSublanguages(tsf ts.ToolStatusFiles, disabledSublanguages map[string]string) ts.ToolStatusFiles {
	out := ts.ToolStatusFiles{}
	for lang, fs := range tsf {
		name := lang
		if displayName, ok := languageQueryIdToDisplayNameMap[lang]; ok {
			name = displayName
		}
		if parentLang, ok := disabledSublanguages[lang]; ok {
			name = parentLang
		}

		if out[name] == nil {
			out[name] = ts.FileSet{}
		}
		out[name] = out[name].Union(fs)
	}
	return out
}

func getAlertCounts(alerts []*ts.LogicalAlert) (map[proto.SecuritySeverity]uint64, map[ts.SeverityLevel]uint64, error) {
	securityCounts := make(map[proto.SecuritySeverity]uint64)
	counts := make(map[ts.SeverityLevel]uint64)

	for _, la := range alerts {
		if la.SecuritySeverityLevel() != proto.SecuritySeverity_NO_SECURITY_SEVERITY {
			securityCounts[la.SecuritySeverityLevel()] += 1
		} else {
			// If no SecuritySeverityLevel is set, consider only SeverityLevel
			counts[la.SeverityLevel] += 1
		}
	}
	return securityCounts, counts, nil
}

// extendPullRequestAlertsResponseWithSeverityCounts populates the response object with counts
// associated with severities of the given alert list
func extendPullRequestAlertsResponseWithSeverityCounts(resp *proto.PullRequestAlertsResponse, alerts []*ts.LogicalAlert) error {
	securityCounts, counts, err := getAlertCounts(alerts)
	if err != nil {
		return err
	}

	resp.SecurityCriticalCount = securityCounts[proto.SecuritySeverity_CRITICAL]
	resp.SecurityHighCount = securityCounts[proto.SecuritySeverity_HIGH]
	resp.SecurityMediumCount = securityCounts[proto.SecuritySeverity_MEDIUM]
	resp.SecurityLowCount = securityCounts[proto.SecuritySeverity_LOW]

	resp.ErrorCount = counts[ts.SeverityLevelError]
	resp.WarningCount = counts[ts.SeverityLevelWarning]
	resp.NoteCount = counts[ts.SeverityLevelNote]
	return nil
}

func serializeAlertTitles(alertsDescription map[ts.RepositoryEID]map[uint32]string) *proto.AlertTitlesResponse {
	resp := &proto.AlertTitlesResponse{}

	for repoId, alertsForRepo := range alertsDescription {
		for alertNumber, title := range alertsForRepo {
			resp.RepositoryIds = append(resp.RepositoryIds, uint64(repoId))
			resp.AlertNumbers = append(resp.AlertNumbers, alertNumber)
			resp.Titles = append(resp.Titles, title)
		}
	}

	return resp
}

func serializeProcessErrors(processErrors []*ts.ProcessError) []*proto.ProcessError {
	var result []*proto.ProcessError
	for _, processError := range processErrors {
		result = append(result, &proto.ProcessError{
			ErrorType: processError.ErrorType.String(),
			Message:   processError.Message,
		})
	}
	return result
}

func serializeDeliveryOrigin(do ts.DeliveryOrigin) proto.DeliveryOrigin {
	switch do {
	case ts.DeliveryOrigin_API:
		return proto.DeliveryOrigin_DELIVERY_ORIGIN_API
	case ts.DeliveryOrigin_MANAGED:
		return proto.DeliveryOrigin_DELIVERY_ORIGIN_MANAGED
	case ts.DeliveryOrigin_DYNAMIC:
		return proto.DeliveryOrigin_DELIVERY_ORIGIN_DYNAMIC
	case ts.DeliveryOrigin_YML:
		return proto.DeliveryOrigin_DELIVERY_ORIGIN_YML
	default:
		return proto.DeliveryOrigin_DELIVERY_ORIGIN_UNKNOWN
	}
}

func serializeSearchDocumentForInsights(searchDocument ts.SearchDocument) (*proto.InsightsAlert, *proto.InsightsAlert, error) {
	repoID, err := strconv.ParseUint(searchDocument.RepositoryID, 10, 64)
	if err != nil {
		return nil, nil, twirp.InternalErrorWith(err)
	}

	var createdAtTimestamp *timestamp.Timestamp
	if searchDocument.CreatedAt != nil {
		createdAtTimestamp = &timestamp.Timestamp{Seconds: searchDocument.CreatedAt.Unix(), Nanos: int32(searchDocument.CreatedAt.Nanosecond())}
	}

	var updatedAtTimestamp *timestamp.Timestamp
	if searchDocument.UpdatedAt != nil {
		updatedAtTimestamp = &timestamp.Timestamp{Seconds: searchDocument.UpdatedAt.Unix(), Nanos: int32(searchDocument.UpdatedAt.Nanosecond())}
	}

	closed, closedAtTimestamp := searchDocument.CalculateAlertClosure()

	alertResoluton, err := ts.NewAlertResolution(searchDocument.Resolution)

	if err != nil {
		return nil, nil, twirp.InternalErrorWith(err)
	}
	resolution := SerializeResolution(alertResoluton)
	securitySeverity := proto.SecuritySeverity(proto.SecuritySeverity_value[searchDocument.Severity])

	updatedAlertPayload := func() *proto.InsightsAlert {
		return &proto.InsightsAlert{
			Id:                  searchDocument.AlertID,
			RepositoryId:        repoID,
			CreatedAt:           createdAtTimestamp,
			UpdatedAt:           updatedAtTimestamp,
			ClosedAt:            closedAtTimestamp,
			Closed:              closed,
			Resolution:          resolution,
			RuleName:            searchDocument.RuleName,
			RuleSarifIdentifier: searchDocument.SarifIdentifier,
			ToolName:            searchDocument.Tool,
			Severity:            securitySeverity,
			PresentOnDefaultRef: searchDocument.FixedOnDefault != nil,
			Number:              searchDocument.Number,
		}
	}

	updatedAlert := updatedAlertPayload()
	var createdAlert *proto.InsightsAlert

	// If alert was created on a different day compared to last update, we need to create the
	// initial revision on that original day, with initial values of the fields.
	if searchDocument.CreatedAt != nil && searchDocument.UpdatedAt != nil {
		createdYear, createdMonth, createdDay := searchDocument.CreatedAt.Date()
		updatedYear, updatedMonth, updatedDay := searchDocument.UpdatedAt.Date()

		if createdYear != updatedYear || createdMonth != updatedMonth || createdDay != updatedDay {
			createdAlert = updatedAlertPayload()

			createdAlert.UpdatedAt = createdAtTimestamp
			createdAlert.ClosedAt = nil
			createdAlert.Closed = false
			createdAlert.Resolution = proto.ResultResolution_NO_RESOLUTION
		}
	}

	return updatedAlert, createdAlert, nil
}
