// Package firewall provides utilities for generating firewall-related comments and telemetry
// when network requests are blocked during agent execution.
package firewall

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"fmt"
	"html/template"
	"net/url"
	"slices"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/jobs"
)

// FirewallStandAloneCommentPrefix is the prefix text used for standalone firewall comments.
const FirewallStandAloneCommentPrefix = "Just as a heads up, I was blocked by some firewall rules while working on your feedback. Expand below for details."

//go:embed firewall_comment.md
var firewallCommentTemplate string

// ParseLocations groups blocked requests by domain/URL/IP and filters to include only
// the top 3 unique commands per location.
func ParseLocations(blockedRequests []BlockedRequest) map[string][]BlockedRequest {
	// Group requests by domain/URL/IP
	domainGroups := make(map[string][]BlockedRequest)
	for _, request := range blockedRequests {
		// Trim leading and trailing whitespace from the request fields
		request.Cmd = strings.TrimSpace(request.Cmd)

		switch {
		case request.URL != "":
			if !isIgnored(request.URL) {
				key := request.URL
				domainGroups[key] = append(domainGroups[key], request)
			}
		case request.Domains != "" && request.Domains != "None":
			// Handle comma separated list of domains
			domains := strings.Split(request.Domains, ",")
			for _, domain := range domains {
				trimmedDomain := strings.TrimSpace(strings.TrimSuffix(domain, "."))
				if trimmedDomain == "" {
					continue
				}
				if strings.Contains(request.RuleSourceComment, "httpOnly: true") {
					trimmedDomain = fmt.Sprintf("%s (HTTP Only)", trimmedDomain)
				}

				if !isIgnored(trimmedDomain) {
					domainGroups[trimmedDomain] = append(domainGroups[trimmedDomain], request)
				}
			}
		case request.IP != "":
			if !isIgnored(request.IP) {
				key := request.IP
				domainGroups[key] = append(domainGroups[key], request)
			}
		default:
			// No action needed for requests without URL, Domains, or IP
		}
	}

	// Filter to include only top 3 unique commands per domain/IP/URL
	for domain, requests := range domainGroups {
		// Create a map to track unique commands
		uniqueCmds := make(map[string]bool)
		uniqueRequests := []BlockedRequest{}

		// Collect unique commands
		for _, req := range requests {
			if req.Cmd != "" && !uniqueCmds[req.Cmd] && len(uniqueRequests) < 3 {
				uniqueCmds[req.Cmd] = true
				uniqueRequests = append(uniqueRequests, req)
			}
		}

		// Replace the original requests with filtered ones
		if len(uniqueRequests) > 0 {
			domainGroups[domain] = uniqueRequests
		}
	}

	return domainGroups
}

func isIgnored(key string) bool {
	// Filter out ignored domains/IPs or unparsable URLs... e.g. _https._tcp.apt.releases.hashicorp.com
	parsedURL, err := url.Parse(key)
	if err == nil {
		// Domains will show up as paths
		hostname := parsedURL.Hostname()
		if hostname == "" {
			hostname = parsedURL.Path
		}
		if slices.Contains(config.DomainIgnoreList, hostname) || strings.HasPrefix(hostname, "_") {
			return true
		}
	}
	return false
}

type templateInput struct {
	Locations            map[string][]BlockedRequest
	FirewallSettingsLink string
}

// GenerateFirewallComment creates a formatted comment explaining firewall blocks
// that occurred during job execution.
func GenerateFirewallComment(blockedRequests []BlockedRequest, job *jobs.Job) (string, error) {
	if len(blockedRequests) == 0 {
		return "", nil
	}

	// We may have filtered out all domains, so return if so
	locations := ParseLocations(blockedRequests)
	if len(locations) == 0 {
		return "", nil
	}

	tmpl, err := template.New("firewall").Parse(firewallCommentTemplate)
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	input := templateInput{
		Locations: locations,
		FirewallSettingsLink: fmt.Sprintf("https://github.com/%s/%s/settings/copilot/coding_agent",
			job.RepoOwner,
			job.RepoName,
		),
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, input)
	if err != nil {
		return "", fmt.Errorf("failed to execute template: %w", err)
	}

	return buf.String(), nil
}

// BlockedRequest represents a network request that was blocked by firewall rules.
// The actual firewall log is filtered down to just blocked requests.
// From: https://github.com/github/sweagentd/blob/c3533ef2651a9661b5de1d768584723864199d7a/runtime/src/callback.ts#L313
type BlockedRequest struct {
	Because           string
	Domains           string
	IP                string
	OriginalIP        string
	URL               string
	Port              string
	RuleSourceComment string
	HasBeenRedirected bool
	Cmd               string
	BlockedAt         string
}

// Cleaned telemetry from PII
type blockedRequestTelemetry struct {
	Because           string `json:"because"`
	Domains           string `json:"domains"`
	URL               string `json:"url"`
	RuleSourceComment string `json:"rule_source_comment"`
	HasBeenRedirected bool   `json:"has_been_redirected"`
	BlockedAt         string `json:"blocked_at"`
}

// GenerateFirewallTelemetry creates telemetry data from blocked requests,
// cleaning any PII before serialization.
func GenerateFirewallTelemetry(l []BlockedRequest) []kvp.Field {
	kvps := make([]kvp.Field, 0)
	if len(l) > 0 {
		blockedRequestTel := []blockedRequestTelemetry{}
		for _, v := range ParseLocations(l) {
			for _, b := range v {
				blockedRequestTel = append(blockedRequestTel, blockedRequestTelemetry{
					Because:           b.Because,
					Domains:           b.Domains,
					URL:               b.URL,
					RuleSourceComment: b.RuleSourceComment,
					HasBeenRedirected: b.HasBeenRedirected,
					BlockedAt:         b.BlockedAt,
				})
			}
		}
		blockedRequestTelJSON, err := json.Marshal(blockedRequestTel)
		if err == nil {
			kvps = append(kvps, kvp.String("job.firewall_blocked", string(blockedRequestTelJSON)))
		} else {
			// Fallback to string representation if JSON marshaling fails
			kvps = append(kvps, kvp.String("job.firewall_blocked", fmt.Sprintf("%+v", blockedRequestTel)))
		}
	}

	return kvps
}
