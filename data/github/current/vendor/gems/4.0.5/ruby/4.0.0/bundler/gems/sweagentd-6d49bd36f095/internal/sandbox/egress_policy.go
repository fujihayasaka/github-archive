package sandbox

import (
	"net/url"
	"slices"
	"strings"

	launchsandbox "github.com/github/launch/services/pb/sandbox"
)

const trafficInspectionFull = "Full"

var requiredHostRules = []*launchsandbox.HostRule{
	{Pattern: "github.com", Action: "Allow"},
	{Pattern: "api.github.com", Action: "Allow"},
	{Pattern: "api.githubcopilot.com", Action: "Allow"},
}

func buildRequiredHostRules(opts ServiceOpts) []*launchsandbox.HostRule {
	patterns := make([]string, 0, len(requiredHostRules)+3)
	for _, rule := range requiredHostRules {
		patterns = append(patterns, rule.Pattern)
	}

	for _, rawURL := range []string{
		opts.GitHubServerURL,
		opts.CopilotAPIURL,
		opts.MissionControlBaseURL,
	} {
		if pattern := hostPatternFromURL(rawURL); pattern != "" {
			patterns = append(patterns, pattern)
		}
	}

	patterns = append(patterns, extractHostPatterns(opts.RequiredFirewallAllowList)...)

	rules := make([]*launchsandbox.HostRule, 0, len(patterns))
	for _, pattern := range patterns {
		rules = appendHostRule(rules, pattern)
	}
	return rules
}

// buildEgressPolicy is the single sandbox entrypoint that takes the per-call
// firewall configuration (FirewallEnabled, FirewallUseDefaultRules,
// FirewallAllowedRules) plus the service-level required + recommended
// allowlists and produces the EgressPolicy that the Launch sandbox API
// expects.
func (s *Service) buildEgressPolicy(params *CreateSandboxParams) *launchsandbox.EgressPolicy {
	if !params.FirewallEnabled {
		return &launchsandbox.EgressPolicy{
			DefaultAction:     "Allow",
			TrafficInspection: trafficInspectionFull,
		}
	}

	policy := &launchsandbox.EgressPolicy{
		DefaultAction:     "Deny",
		TrafficInspection: trafficInspectionFull,
	}

	policy.HostRules = append(policy.HostRules, s.requiredHosts...)

	if params.FirewallUseDefaultRules {
		for _, pattern := range defaultRuleHostPatterns {
			policy.HostRules = appendHostRule(policy.HostRules, pattern)
		}
	}

	for _, pattern := range params.FirewallAllowedRules {
		policy.HostRules = appendHostRule(policy.HostRules, pattern)
	}

	return policy
}

func appendHostRule(rules []*launchsandbox.HostRule, pattern string) []*launchsandbox.HostRule {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return rules
	}
	if slices.ContainsFunc(rules, func(rule *launchsandbox.HostRule) bool {
		return rule.Pattern == pattern
	}) {
		return rules
	}
	return append(rules, &launchsandbox.HostRule{
		Pattern: pattern,
		Action:  "Allow",
	})
}

func hostPatternFromURL(rawURL string) string {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" {
		return ""
	}

	parsedURL, err := url.Parse(rawURL)
	if err != nil || parsedURL.Host == "" {
		parsedURL, err = url.Parse("https://" + rawURL)
		if err != nil {
			return ""
		}
	}

	return parsedURL.Hostname()
}
