// The redact package should be used to redact possibly-sensitive messages from
// user input, for example in query strings. It is a rough port of
// https://github.com/github/redacting-logger.
//
// It has the following differences from redacting-logger:
//
// 1. It is not a logging package. Use it where you log strings.
// 2. It only supports redacting strings, not nested structures.
// 3. The regex patterns are combined rather than evaluated one-by-one.
package redact

import (
	"regexp"
	"strings"
)

const redaction = "[REDACTED]"

// patterns is sourced from https://github.com/github/redacting-logger/blob/066b2e0116e6f7a6c09d78b11c56eddf58aa101b/lib/patterns/default.rb
var patterns = []string{
	// GitHub Personal Access Token
	// https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/
	`ghp_[A-Za-z0-9]{36,}|[0-9A-Fa-f]{40,}`,
	`github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}`, // Fine Grained
	`ghs_[a-zA-Z0-9]{36}`,                        // Temporary Actions Tokens

	// JWT Token
	// https://en.wikipedia.org/wiki/JSON_Web_Token
	`\b(ey[a-zA-Z0-9]{17,}\.ey[a-zA-Z0-9/\\_-]{17,}\.(?:[a-zA-Z0-9/\\_-]{10,}={0,2})?)(?:['|"|\n|\r|\s|\x60|;]|$)`,

	// PEM Private Keys
	// https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail
	`(?i)-----BEGIN[ A-Z0-9_-]{0,100}PRIVATE KEY( BLOCK)?-----[\s\S-]*KEY( BLOCK)?----`,

	// Slack Webhook
	// https://api.slack.com/messaging/webhooks
	`https://hooks\.slack\.com/services/[a-zA-Z0-9]{9,}/[a-zA-Z0-9]{9,}/[a-zA-Z0-9]{24}`,

	// Slack Workflows
	`https://hooks\.slack\.com/workflows/[a-zA-Z0-9]{9,}/[a-zA-Z0-9]{9,}/[0-9]+?/[a-zA-Z0-9]{24}`,

	// Slack Trigger
	// https://slack.com/help/articles/360041352714-Build-a-workflow--Create-a-workflow-that-starts-outside-of-Slack
	`https://hooks\.slack\.com/triggers/.+`,

	// Slack Tokens
	// https://api.slack.com/authentication/token-types
	`xoxp-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9a-f]{6,})`,
	`xoxb-(?:[0-9]{7,})-(?:[A-Za-z0-9]{14,})`,
	`xoxs-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9a-f]{7,})`,
	`xoxa-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9a-f]{7,})`,
	`xoxo-(?:[0-9]{7,})-(?:[A-Za-z0-9]{14,})`,
	`xoxa-2-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9a-f]{7,})`,
	`xoxr-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[0-9a-f]{7,})`,
	`xoxb-(?:[0-9]{7,})-(?:[0-9]{7,})-(?:[A-Za-z0-9]{14,})`,

	// Vault Tokens
	// https://github.com/hashicorp/vault/issues/27151
	`[sbr]\.[a-zA-Z0-9]{24,}`,   // <= 1.9.x
	`hv[sbr]\.[a-zA-Z0-9]{24,}`, // >= 1.10

	// RubyGems Token
	// https://guides.rubygems.org/api-key-scopes/
	`rubygems_[0-9a-f]{48}`,
}

var combinedRegex = regexp.MustCompile(strings.Join(patterns, "|"))

func Redact(s string) string {
	return combinedRegex.ReplaceAllString(s, redaction)
}
