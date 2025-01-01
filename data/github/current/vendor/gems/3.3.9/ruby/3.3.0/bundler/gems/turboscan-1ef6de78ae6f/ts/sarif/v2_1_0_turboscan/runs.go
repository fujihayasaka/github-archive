package v210turboscan

import (
	"strings"

	"github.com/pkg/errors"
)

// hasUniqueWorkingDirectory returns the working directory if one exists
// or an empty string for comparison checks in `isMergeableWith` method.
func (r *Run) hasUniqueWorkingDirectory() (string, bool) {
	s := make(map[string]struct{})
	if len(r.Invocations) == 0 {
		return "", true
	}
	for _, i := range r.Invocations {
		if i.WorkingDirectory == nil {
			return "", true
		}
		if i.WorkingDirectory != nil {
			uri := i.WorkingDirectory.Uri
			_, ok := s[uri]
			if !ok {
				s[uri] = struct{}{}
			}
		}
	}
	return r.Invocations[0].WorkingDirectory.Uri, len(s) == 1 // it still returns the first invocations working directory uri.
}

func (r *Run) AutomationID() string {
	if r.AutomationDetails == nil {
		return ""
	}
	return r.AutomationDetails.Id
}

func (r *Run) JobRunUuid() string {
	if r.Properties == nil {
		return ""
	}
	return r.Properties.JobRunUuid
}

// isMergeableWith returns nil if Run r is mergeable with Run b or returns an error.
func (r *Run) isMergeableWith(b *Run) error {
	if r.Tool == nil || r.Tool.Driver == nil || b.Tool == nil || b.Tool.Driver == nil {
		return errors.New("invalid tool object when trying to combine runs")
	}
	if r.Tool.Driver.Name != b.Tool.Driver.Name {
		return errors.New("incompatible tool names when trying to combine runs")
	}
	if r.AutomationID() != b.AutomationID() {
		return errors.New("incompatible automation details when trying to combine runs")
	}

	rWD, ok := r.hasUniqueWorkingDirectory()
	if !ok {
		return errors.New("incompatible invocations when trying to combine runs")
	}
	bWD, ok := b.hasUniqueWorkingDirectory()
	if !ok {
		return errors.New("incompatible invocations when trying to combine runs")
	}
	if rWD != bWD {
		return errors.New("incompatible invocations when trying to combine runs")
	}

	return nil
}

func (r *Run) HasUnsuccessfulInvocations() bool {
	for _, invoc := range r.Invocations {
		if !invoc.ExecutionSuccessful {
			return true
		}
	}
	return false
}

func (r *Run) HasOnlySuccessfulInvocations() bool {
	return !r.HasUnsuccessfulInvocations()
}

// Merge returns a new Run into a single one by combining
// results, rules, invocations, notifications and automation IDs.
// If there are successful and failed runs only the successful ones will get merged.
// Previously this was called CombineRunsForAToolIDPair in the sarif package.
// Note: This method is fragile as there should not be a need
// of combining Runs. However, we originally decided to combine runs from
// different configurations of a tool that appear in the same SARIF file, and
// this method is meant to support that use-case.
// Please think carefully before using this method anywhere else.
// See https://github.com/github/code-scanning/issues/1555 for deprecation issue.
func (r *Run) Merge(b *Run) (*Run, error) {
	if err := r.isMergeableWith(b); err != nil {
		return nil, err
	}
	tc := *r.Tool.Driver
	tc.Rules = append(tc.Rules, b.Tool.Driver.Rules...)

	out := Run{}
	out.Tool = &Tool{Driver: &tc}
	out.Tool.Extensions = append(out.Tool.Extensions, r.Tool.Extensions...)
	extensionsOffset := len(out.Tool.Extensions)
	out.Tool.Extensions = append(out.Tool.Extensions, b.Tool.Extensions...)
	for _, result := range b.Results {
		if result.Rule != nil && result.Rule.ToolComponent != nil && result.Rule.ToolComponent.Index >= 0 {
			result.Rule.ToolComponent.Index += len(r.Tool.Extensions)
		}
	}
	out.Results = append(out.Results, r.Results...)
	out.Results = append(out.Results, b.Results...)

	if len(r.Tool.Driver.Notifications) > 0 || len(b.Tool.Driver.Notifications) > 0 {
		out.Tool.Driver.Notifications = r.Tool.Driver.Notifications
		out.Tool.Driver.Notifications = append(out.Tool.Driver.Notifications, b.Tool.Driver.Notifications...)
	}

	out.Properties = &RunPropertyBag{}
	if r.Properties != nil {
		out.Properties.MetricResults = append(out.Properties.MetricResults, r.Properties.MetricResults...)
	}
	if b.Properties != nil {
		for _, result := range b.Properties.MetricResults {
			if result.Rule != nil && result.Rule.ToolComponent != nil && result.Rule.ToolComponent.Index >= 0 {
				result.Rule.ToolComponent.Index += len(r.Tool.Extensions)
			}
		}
		out.Properties.MetricResults = append(out.Properties.MetricResults, b.Properties.MetricResults...)
	}

	// Update notification references
	notificationsOffset := len(r.Tool.Driver.Notifications)
	for _, invocation := range b.Invocations {
		for _, n := range invocation.ToolExecutionNotifications {
			if n.Descriptor != nil {
				tcInd, _, err := b.Tool.toolComponentFromReference(n.Descriptor)
				if err != nil {
					return nil, err
				}
				if tcInd.IsDriver() {
					if n.Descriptor.Index >= 0 {
						n.Descriptor.Index += notificationsOffset
					}
				} else { // nolint:gocritic
					// must be extension, need to update if based on index instead of guid
					if n.Descriptor.ToolComponent.Index >= 0 {
						n.Descriptor.ToolComponent.Index += extensionsOffset
					}
				}

			}
		}
	}
	out.Invocations = r.Invocations
	out.Invocations = append(out.Invocations, b.Invocations...)

	out.AutomationDetails = r.AutomationDetails // since a.AutomationDetails == b.AutomationDetails (in guard)
	return &out, nil
}

// normalise is a delegate method where we can run our
// resolving logic for varius lookups by id or other means and
// aggregate all the missing information. Currently, its resolving
// locations within physical alerts by replacing references with
// concrete instances. The idea is to run this before we do any
// sort of merge on these runs so that we rely on the actual values
// rather than their references. Though arguably, its better to have
// references than values but because of `Merge` method, we would
// have to do preprocessing.
func (r *Run) normalise() {
	r.normaliseLocations()
	r.normaliseRelatedLocations()
}

// RuleLookup returns the Rule object indicated by the given data.
//
// There are a few ways in which a Rule can be associated with a (metric) result:
//  1. ruleId: The rule identifier is included in the result.
//  2. ruleRef: A reference to a rule (See §3.52.3)
//     2a. rule.id can be a ruleId + an additional hierarchical component
//     2b. rule.index is defined with the same semantics as ruleIndex
//  3. ruleIndex: The index of the array in the ruleDescriptors section of the run
func (r *Run) RuleLookup(ruleID string, ruleIndex int, ruleRef *ReportingDescriptorReference) (*Rule, ToolComponentIndicator, error) {
	var rule *Rule

	// Determine the correct tool component
	// (see §3.52.7)
	tcInd, tc, err := r.Tool.toolComponentFromReference(ruleRef)
	if err != nil {
		return nil, ToolComponentUnknown, err
	}

	rules := tc.Rules

	switch {
	case ruleID != "":
		rule = RuleFromRuleId(rules, ruleID)
		if rule == nil {
			return undetailedRule(ruleID), tcInd, nil
		}
	case ruleRef != nil && ruleRef.Id != "":
		// Try first with the original ID, and then try to remove the potential trailing hierarchy element
		lastSlash := strings.LastIndex(ruleRef.Id, "/")
		rule = RuleFromRuleId(rules, ruleRef.Id)
		if rule == nil && lastSlash != -1 {
			// The ID is hierarchical (e.g., a/b/c), try by removing the last hierarchical element
			// See (See §3.52.4)
			rule = RuleFromRuleId(rules, ruleRef.Id[:lastSlash])
		}
		if rule == nil {
			return undetailedRule(ruleRef.Id), tcInd, nil
		}
	case ruleRef != nil && ruleRef.Index > -1:
		// We expect most cases in which Rule is
		// defined to have an index.  The only alternative field would be
		// a GUID, that we currently do not consider.
		rule = RuleFromRuleIndex(rules, uint(ruleRef.Index))
		if rule == nil {
			return nil, tcInd, errors.Errorf("rule.index %d not found", ruleRef.Index)
		}
	case ruleIndex > -1:
		rule = RuleFromRuleIndex(rules, uint(ruleIndex))
		if rule == nil {
			return nil, tcInd, errors.Errorf("ruleIndex %d not found", ruleIndex)
		}
	default:
		rule = UnknownRule
	}
	return rule, tcInd, nil
}

func (r *Run) LookupNotification(notification *Notification) (*ToolComponent, *ReportingDescriptor, error) {
	_, tc, err := r.Tool.toolComponentFromReference(notification.Descriptor)
	if err != nil {
		return nil, nil, err
	}

	if notification.Descriptor.Index > len(tc.Notifications) {
		return nil, nil, errors.Errorf("notification.index %d not found", notification.Descriptor.Index)
	}

	return tc, tc.Notifications[notification.Descriptor.Index], nil
}
