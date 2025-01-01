package alerts

import (
	"context"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/sarif"
	"golang.org/x/exp/maps"

	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/pkg/errors"
)

const messageMaxSize = 4096

var ErrMaxRepeatedAlertExceeded = errors.New("too many identical alerts")
var ReGUID = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$`)

// Builder is responsible for building a new set of alerts
// The Build() function returns a slice of PhysicalAlert where
// they are primed to be stored in the database.
// That method receives a SARIF struct, where it will use it to
// build the pysical alerts.
// Note the Builder only construct Alerts thus it has no dependency
// on the database or however they are persisted
type Builder struct {
	analysis *ts.Analysis
	limits   *limits.Table

	// Cache to distinguish physical alerts with the same stable id
	locIndexesCache          map[StableAlertIdentifier]uint8
	fileClassificationsCache map[string]ts.FileClassification
}

// NewAlertsBuilder instantiates a new Alerts Builder to be used to
// create Physical alerts from a SARIF delivery
func NewAlertsBuilder(analysis *ts.Analysis, lm *limits.Table) *Builder {

	return &Builder{
		analysis: analysis,
		limits:   lm,

		locIndexesCache:          make(map[StableAlertIdentifier]uint8),
		fileClassificationsCache: make(map[string]ts.FileClassification),
	}
}

func regionFromSARIF(in *v2_1_0.Region) (ts.Region, error) {
	if in == nil {
		// If there's no region specified we use this magic region of all zeros.
		// When returning this information to dotcom this is converted to a region
		// covering the first line of the file, but we may change this behavior later.
		return ts.Region{
			StartLine:   0,
			EndLine:     0,
			StartColumn: 0,
			EndColumn:   0,
		}, nil
	}

	// Because we don't have the source code here, the correct default
	// value for EndColumn (the column after the last column in the
	// line, excluding new line characters) cannot be determined.  We
	// keep it as 0 and have to interpret it correctly when displaying
	// results.
	out := ts.Region{}
	// These guards against negative values should be able to be removed once we
	// start rejecting SARIF files that do not satisfy the JSON schema, as that
	// requires all of these values to be positive, if present.
	if in.StartLine > 0 {
		out.StartLine = uint32(in.StartLine)
	}
	if in.EndLine > 0 {
		out.EndLine = uint32(in.EndLine)
	}
	if in.StartColumn > 0 {
		out.StartColumn = uint32(in.StartColumn)
	}
	if in.EndColumn > 0 {
		out.EndColumn = uint32(in.EndColumn)
	}

	if out.EndLine == 0 {
		out.EndLine = out.StartLine
	}

	if out.StartColumn == 0 {
		out.StartColumn = 1
	}

	if out.StartLine > out.EndLine {
		// NOTE: We patch this value because codeQL suffers from this issue.
		// Once CodeQL has been fixed, we should convert this into an error:
		// return ts.Region{}, errors.New("startLine should be less or equal than endLine")
		out.EndLine = out.StartLine
	}

	if out.StartLine == out.EndLine && out.EndColumn != 0 && out.StartColumn > out.EndColumn {
		// NOTE: We patch this value because codeQL suffers from this issue.
		// Once CodeQL has been fixed, we should convert this into an error:
		// return ts.Region{}, errors.New("startColumn should be less or equal than endColumn for single line regions")
		out.EndColumn = out.StartColumn
	}

	return out, nil
}

// severityFromSarifResult returns the severity level of the result We
// use the severity defined in the result (if present) and fall-back
// to the severity of the rule otherwise. If neither the result nor
// rule specify a severity, we default to None.
func severityFromSarifResult(result *v2_1_0.Result, rule *v2_1_0.Rule) (ts.SeverityLevel, error) {
	if v, ok := result.Level.(string); ok {
		return ts.NewSeverityLevel(v)
	}

	if rule.DefaultConfiguration != nil && rule.DefaultConfiguration.Level != "" {
		return ts.NewSeverityLevel(rule.DefaultConfiguration.Level)
	}

	return ts.SeverityLevelNone, nil
}

// securitySeverityFromSarifResult returns the security severity value of the result We
// use the security severity defined in the result (if present) and fall-back
// to the security severity of the rule otherwise. If neither the result nor
// rule specify a severity, we default to nil.
func (b *Builder) securitySeverityFromSarifResult(result *v2_1_0.Result, rule *v2_1_0.Rule) (*float64, error) {
	if result.Properties != nil && result.Properties.SecuritySeverity != "" {
		f, err := strconv.ParseFloat(result.Properties.SecuritySeverity, 64)
		if err != nil {
			return nil, errors.Errorf("invalid security severity value, is not a number: %s",
				result.Properties.SecuritySeverity)
		}

		return &f, nil
	}

	if rule.Properties != nil && rule.Properties.SecuritySeverity != "" {
		f, err := strconv.ParseFloat(rule.Properties.SecuritySeverity, 64)
		if err != nil {
			return nil, errors.Errorf("invalid security severity value, is not a number: %s",
				result.Properties.SecuritySeverity)
		}

		return &f, nil
	}

	return nil, nil
}

func locationFromSarifResult(result *v2_1_0.Result, checkoutURI ts.CheckoutURI) (*Location, error) {
	if len(result.Locations) == 0 {
		return nil, errors.New("locationFromSarifResult: expected at least one location")
	}
	if result.Locations[0].PhysicalLocation == nil {
		return nil, errors.New("locationFromSarifResult: expected a physical location")
	}
	loc := result.Locations[0].PhysicalLocation
	if loc.ArtifactLocation == nil || loc.ArtifactLocation.Uri == "" {
		return nil, errors.New("locationFromSarifResult: expected artifact location")
	}
	filePath, err := sarif.URIToPath(loc.ArtifactLocation.Uri, checkoutURI)
	if err != nil {
		return nil, err
	}
	if filePath == "" {
		return nil, errors.New("locationFromSarifResult: artifact location cannot be parsed to a file path")
	}

	var snippet *ts.Snippet
	if loc.ContextRegion != nil && loc.ContextRegion.Snippet != nil {
		region, err := regionFromSARIF(loc.ContextRegion)
		if err != nil {
			return nil, err
		}

		snippet = &ts.Snippet{
			Region: region,
			Text:   ts.Truncate(loc.ContextRegion.Snippet.Text, 4096),
		}
	}

	region, err := regionFromSARIF(loc.Region)
	if err != nil {
		return nil, err
	}

	return &Location{
		FilePath:    filePath,
		Fingerprint: result.PartialFingerprints["primaryLocationLineHash"], // CodeQL-specific output
		Region:      region,
		Snippet:     snippet,
	}, nil
}

func (b *Builder) BuildCodeFlows(codeFlowsSarif []*v2_1_0.CodeFlow, checkoutURI ts.CheckoutURI) (ts.CodeFlows, error) {
	var codeFlows ts.CodeFlows

	for cfIdx, codeFlow := range codeFlowsSarif {
		for tfIdx, threadFlow := range codeFlow.ThreadFlows {
			for stepIdx, location := range threadFlow.Locations {
				if location.Location == nil {
					return nil, errors.New("buildCodeFlows: expected location")
				}
				if location.Location.PhysicalLocation == nil {
					return nil, errors.New("buildCodeFlows: expected physical location")
				}
				// TODO: PhysicalLocations might be references to
				// run.threadFlowLocations to save space (see 3.14.19).
				// Currently CodeQL does not output such SARIF, but it may
				// in the future, and other tools may also.
				pl := location.Location.PhysicalLocation
				region, err := regionFromSARIF(pl.Region)
				if err != nil {
					return nil, err
				}
				var message *string
				if location.Location.Message != nil {
					truncMessage := ts.Truncate(location.Location.Message.Text, messageMaxSize)
					message = &truncMessage
				}
				if pl.ArtifactLocation == nil {
					return nil, errors.New("buildCodeFlows: expected artifact location")
				}
				filePath, err := sarif.URIToPath(pl.ArtifactLocation.Uri, checkoutURI)
				if err != nil {
					return nil, err
				}
				codeFlows = append(codeFlows,
					ts.CodeFlow{
						FilePath:        filePath,
						Region:          region,
						Message:         message,
						CodeFlowIndex:   uint32(cfIdx),
						ThreadFlowIndex: uint32(tfIdx),
						StepIndex:       uint32(stepIdx),
					})
			}
		}
	}

	return ts.SortCodeFlows(codeFlows), nil
}

func (b *Builder) buildRelatedLocations(relatedLocations []*v2_1_0.Location, checkoutURI ts.CheckoutURI) ([]*ts.RelatedLocation, error) {
	var locations []*ts.RelatedLocation
	for _, relatedLocation := range relatedLocations {
		if relatedLocation.PhysicalLocation == nil {
			return nil, errors.New("buildRelatedLocations:expected physical location")
		}

		var message string
		if relatedLocation.Message != nil {
			message = ts.Truncate(relatedLocation.Message.Text, messageMaxSize)
		}

		if relatedLocation.PhysicalLocation.ArtifactLocation == nil {
			return nil, errors.New("buildRelatedLocations: expected artifact location")
		}

		filePath, err := sarif.URIToPath(relatedLocation.PhysicalLocation.ArtifactLocation.Uri, checkoutURI)
		if err != nil {
			return nil, err
		}

		location := ts.RelatedLocation{
			RepositoryID:     b.analysis.RepositoryID,
			FilePath:         filePath,
			Message:          message,
			ReplacementIndex: uint32(relatedLocation.Id),
		}

		if relatedLocation.PhysicalLocation.Region != nil {
			location.Region, err = regionFromSARIF(relatedLocation.PhysicalLocation.Region)
			if err != nil {
				return nil, err
			}
		}

		locations = append(locations, &location)
	}
	return locations, nil
}

// checkoutURIForRun prefers the WorkingDirectory provided in the Run, falling
// back to checkoutURI (which is ultimately an API parameter). The latter should
// be deprecated and removed at some point (see
// https://github.com/github/code-scanning/issues/2039), after which this logic
// can be removed.
func checkoutURIForRun(run *v2_1_0.Run, in ts.CheckoutURI) ts.CheckoutURI {
	if len(run.Invocations) == 1 && run.Invocations[0].WorkingDirectory != nil && run.Invocations[0].WorkingDirectory.Uri != "" {
		return ts.ToCheckoutURI(run.Invocations[0].WorkingDirectory.Uri)
	}
	return in
}

// Build Physical alerts and their dependencies based on the SARIF
// definition given
// This will return a slice of non-persisted PhysicalAlert.
func (b *Builder) Build(ctx context.Context, run *v2_1_0.Run, checkoutURI ts.CheckoutURI) ([]*ts.PhysicalAlert, error) {
	var alerts []*ts.PhysicalAlert
	var errs []error

	coURI := checkoutURIForRun(run, checkoutURI)
	for resIdx, result := range run.Results {
		alert, err := b.buildAlert(run, resIdx, result, coURI)
		if err != nil {
			if errors.Is(err, ErrMaxRepeatedAlertExceeded) {
				// Ignore repeated errors after the limit
				continue
			}

			// Only store up to 20 errors
			if len(errs) <= 20 {
				errs = append(errs, err)
			}
		} else {
			alerts = append(alerts, alert)
		}
	}

	// TODO: Merge this in the main logic
	for _, a := range alerts {
		rule, ok := b.analysis.Rules[a.RuleSarifIdentifier]
		if !ok {
			errs = append(errs, ErrRuleNotFound)
			continue
		}
		a.RuleID = rule.ID

		// If no severity was provided for the alert, use the severity of the rule
		if a.SeverityLevel == ts.SeverityLevelNone {
			a.SeverityLevel = rule.SeverityLevel
		}
		a.Weight = ts.MagicWeight(a.SeverityLevel, a.SecuritySeverityLevel(), rule.PrecisionLevel)
	}

	// Enforce limits on alerts
	alerts, warnings := applyLimitsToPhysicalAlerts(b.limits, alerts)

	errs = append(errs, warnings...)

	return alerts, JoinErrors(errs)
}

var ErrResultExpected = errors.New("expected a result message")

func (b *Builder) buildAlert(
	run *v2_1_0.Run,
	resIdx int,
	result *v2_1_0.Result,
	checkoutURI ts.CheckoutURI) (*ts.PhysicalAlert, error) {

	suppressed, err := sarif.Suppressed(result)
	if err != nil {
		return nil, err
	}

	sarifRule, _, err := sarif.RuleFromResult(run, result)
	if err != nil {
		return nil, err
	}

	location, err := locationFromSarifResult(result, checkoutURI)
	if err != nil {
		return nil, err
	}

	if result.Message == nil || result.Message.Text == "" {
		return nil, ErrResultExpected
	}
	message := ts.Truncate(result.Message.Text, messageMaxSize)

	messageMarkdown := ts.Truncate(result.Message.Markdown, messageMaxSize)

	severityLevel, err := severityFromSarifResult(result, sarifRule)
	if err != nil {
		return nil, err
	}

	securitySeverity, err := b.securitySeverityFromSarifResult(result, sarifRule)
	if err != nil {
		return nil, err
	}

	// TODO handle errors
	baseSid := NewStableID(
		b.analysis.RepositoryID,
		sarifRule.Id,
		*location,
	)

	i := b.locIndexesCache[baseSid]
	if i > 254 {
		// Do not consider more than 255 "identical" alerts
		return nil, ErrMaxRepeatedAlertExceeded
	}
	sid := baseSid.PutIndex(i)
	b.locIndexesCache[baseSid]++

	classification, ok := b.fileClassificationsCache[location.FilePath]
	if !ok {
		classification = classifyFileByPath(location.FilePath)
		b.fileClassificationsCache[location.FilePath] = classification
	}

	var guid *string
	if ReGUID.MatchString(result.Guid) {
		// convert GUIDs to lower case before storing for consistency
		downcasedGuid := strings.ToLower(result.Guid)
		guid = &downcasedGuid
	}

	now := sqltime.Now()
	pa := &ts.PhysicalAlert{
		RepositoryID:          b.analysis.RepositoryID,
		AnalysisID:            b.analysis.ID,
		Analysis:              b.analysis,
		RuleSarifIdentifier:   sarifRule.Id,
		StableAlertIdentifier: sid[:],
		Fingerprint:           location.Fingerprint,
		FilePath:              location.FilePath,
		Region:                location.Region,
		Suppressed:            suppressed,
		Message:               message,
		MessageMarkdown:       messageMarkdown,
		SeverityLevel:         severityLevel,
		SecuritySeverity:      securitySeverity,
		FileClassification:    classification,
		Snippet:               location.Snippet,
		GUID:                  guid,
		LastStateChangeAt:     now,
	}

	codeFlows, err := b.BuildCodeFlows(result.CodeFlows, checkoutURI)
	if err != nil {
		return nil, err
	}

	if len(codeFlows) > 0 {
		documentID := ts.CodeFlowsDocumentID(resIdx)
		pa.CodeFlowsDocumentID = &documentID
		pa.CodeFlowsDocument = &ts.CodeFlowsDocument{
			RepositoryID: pa.RepositoryID,
			Document:     codeFlows,
		}
	}

	pa.RelatedLocations, err = b.buildRelatedLocations(result.RelatedLocations, checkoutURI)
	if err != nil {
		return nil, err
	}

	return pa, nil

}

// applyLimitsToPhysicalAlerts returns a new slice of alerts after applying limits to it.
// If limits were applied a message is included.
func applyLimitsToPhysicalAlerts(t *limits.Table, alerts []*ts.PhysicalAlert) ([]*ts.PhysicalAlert, []error) {
	type awp struct {
		alert   *ts.PhysicalAlert
		penalty int
	}
	var messages []error
	var droppedCount int
	var alertsOut []*ts.PhysicalAlert

	if len(alerts) > t.ResPerRunLimit {
		// Sort the alerts according to a precomputed penalty score.
		// Lower penalty scores mean that an alert is less likely to be removed.
		alertWithPenalty := make([]awp, len(alerts))
		for i, a := range alerts {
			alertWithPenalty[i] = awp{
				alert:   a,
				penalty: computePenaltyForAlert(a),
			}
		}
		sort.SliceStable(alertWithPenalty, func(i, j int) bool {
			return alertWithPenalty[i].penalty < alertWithPenalty[j].penalty
		})

		droppedCount = len(alerts) - t.ResPerRunLimit
		alertsOut = make([]*ts.PhysicalAlert, t.ResPerRunLimit)
		for i, a := range alertWithPenalty {
			if i >= t.ResPerRunLimit {
				break
			}
			alertsOut[i] = a.alert
		}
		// TODO: We could iterate over the remaining items to write a better message
		messages = append(
			messages,
			limits.LimitError{
				Name:               "results",
				Dropped:            droppedCount,
				Max:                t.ResPerRunLimit,
				Total:              t.ResPerRunLimit + droppedCount,
				AnalysisMessageKey: string(ts.MessageSarifSoftLimitResultsPerRun),
			},
		)
	} else {
		alertsOut = alerts
	}

	// Apply other limits inside within each alert
	// 1. Locations.
	droppedCount = 0
	alertCount := 0
	ruleSarifIds := map[string]struct{}{}
	for _, a := range alertsOut {
		if len(a.RelatedLocations) > t.LocPerResLimit {
			alertCount += 1
			droppedCount += len(a.RelatedLocations) - t.LocPerResLimit
			a.RelatedLocations = a.RelatedLocations[:t.LocPerResLimit]
			ruleSarifIds[a.RuleSarifIdentifier] = struct{}{}
		}
	}
	if droppedCount > 0 {
		messages = append(
			messages,
			limits.LimitError{
				Name:               "relatedLocations",
				RuleSarifIds:       maps.Keys(ruleSarifIds),
				AlertCount:         alertCount,
				Max:                t.LocPerResLimit,
				Dropped:            droppedCount,
				Total:              t.LocPerResLimit + droppedCount,
				AnalysisMessageKey: string(ts.MessageSarifSoftLimitRelatedLocations),
			},
		)
	}

	// 2. ThreadFlows
	alertCount = 0
	droppedCount = 0
	oldCount := 0
	ruleSarifIds = map[string]struct{}{}
	for _, a := range alertsOut {
		if a.CodeFlowsDocument != nil && len(a.CodeFlowsDocument.Document) > t.StepsPerResLimit {
			alertCount += 1
			oldLen := len(a.CodeFlowsDocument.Document)
			oldCount += oldLen
			a.CodeFlowsDocument.Document = filterCodeFlows(a.CodeFlowsDocument.Document, t.StepsPerResLimit)
			droppedCount += oldLen - len(a.CodeFlowsDocument.Document)
			ruleSarifIds[a.RuleSarifIdentifier] = struct{}{}
		}
	}
	if droppedCount > 0 {
		messages = append(
			messages,
			limits.LimitError{
				Name:               "threadFlows",
				RuleSarifIds:       maps.Keys(ruleSarifIds),
				AlertCount:         alertCount,
				Max:                t.StepsPerResLimit,
				Dropped:            droppedCount,
				Total:              t.StepsPerResLimit + droppedCount,
				AnalysisMessageKey: string(ts.MessageSarifSoftLimitThreadFlows),
			},
		)
	}

	return alertsOut, messages
}

func computePenaltyForAlert(alert *ts.PhysicalAlert) int {
	// Depending on the Severities we assign an increasing penalty, based on the
	// relative importance of the severities as dictated by their weight
	// The penalty scoring could include other factors like classifications

	// Precision is currently not used for this.
	weight := ts.MagicWeight(alert.SeverityLevel, alert.SecuritySeverityLevel(), ts.PrecisionLevelUnknown)

	// The penalty is the opposite of the weight
	return -int(weight)
}

// filterCodeFlows selects a subset of codeFlows such that the total number of steps is below the limit.
// We prefer thread flows that:
// - Have a unique initial-final location pair
// - Occur early in the list
// - Are small enough to fit within the limit
// As pre-check for this method we need to ensure that all codeFlows are single threaded. If this is not the case, we
// perform a much simpler truncation.
func filterCodeFlows(flows ts.CodeFlows, stepsLimit int) ts.CodeFlows {
	if !allThreadsAreSingleThreaded(flows) {
		return flows[:stepsLimit]
	}

	// As all codeflows are in the same slice, we need some book keeping to identify the start and end of each.
	// Rather then caring about the specific location, we construct a key that accounts for filepath and region
	type metadata struct {
		initialLocationKey   string
		finalLocationKey     string
		size                 uint32
		initialLocationIndex int
		finalLocationIndex   int
	}

	book := make(map[uint32]*metadata)
	for i, flow := range flows {
		m, ok := book[flow.CodeFlowIndex]
		if !ok {
			book[flow.CodeFlowIndex] = &metadata{}
			m = book[flow.CodeFlowIndex]
		}

		if flow.StepIndex == 0 {
			m.initialLocationIndex = i
		}
		if flow.StepIndex >= m.size {
			m.finalLocationIndex = i
			m.size = flow.StepIndex
		}
	}

	// Compute keys to identify the start and end of each thread flow
	for _, m := range book {
		initialFlow := flows[m.initialLocationIndex]
		m.initialLocationKey = fmt.Sprintf("%v %v", initialFlow.FilePath, initialFlow.Region)

		finalFlow := flows[m.finalLocationIndex]
		m.finalLocationKey = fmt.Sprintf("%v %v", finalFlow.FilePath, finalFlow.Region)
	}

	toKeep := make(map[uint32]bool)
	seenInitialLocations := make(map[string]bool)
	seenFinalLocations := make(map[string]bool)

	// Add all the flows that have unique initial and final locations
	outSize := 0
	for i := 0; i < len(book); i++ {
		m := book[uint32(i)]
		if seenInitialLocations[m.initialLocationKey] && seenFinalLocations[m.finalLocationKey] {
			continue
		}

		// Make sure we have enough space
		size := int(m.size + 1)
		if outSize+size > stepsLimit {
			continue
		}
		outSize += size

		seenInitialLocations[m.initialLocationKey] = true
		seenFinalLocations[m.finalLocationKey] = true
		toKeep[uint32(i)] = true
	}

	// Add any other flow that fits
	for i := 0; i < len(book); i++ {
		// Skip flows that are already in the output
		if toKeep[uint32(i)] {
			continue
		}
		m := book[uint32(i)]

		// Make sure we have enough space
		size := int(m.size + 1)
		if outSize+size > stepsLimit {
			continue
		}
		outSize += size
		toKeep[uint32(i)] = true
	}

	// Filter the list
	filtered := make(ts.CodeFlows, 0, len(flows))
	for _, flow := range flows {
		if toKeep[flow.CodeFlowIndex] {
			filtered = append(filtered, flow)
		}
	}

	return filtered
}

func allThreadsAreSingleThreaded(flows ts.CodeFlows) bool {
	for _, flow := range flows {
		if flow.ThreadFlowIndex != 0 {
			return false
		}
	}
	return true
}
