// Package exceptions provides exception reporting and redaction utilities.
package exceptions

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	httpexporter "github.com/github/go-exceptions/exporters/http"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/sweagentd/internal/goerrors"
)

var (
	// Injected at buildtime with `-ldflags "-X github.com/github/sweagentd/internal/observability/exceptions.gitRoot=<whatever the git root is>"`
	gitRoot string
)

// NewReporter configures a new exceptions reporter based on the config.
// It prints reports to stderr in development environment, but sends them to
// Failbotg (which is proxied to Sentry) in production.
func NewReporter(
	isDevelopment bool,
	serviceName,
	environment,
	sha,
	ref string,
	logger log.Logger,
) (*exceptions.Reporter, error) {
	var err error
	var exporter exceptions.Exporter = writer.NewExporter(os.Stderr)

	if !isDevelopment {
		exporter, err = httpexporter.NewExporter()
		if err != nil {
			return nil, err
		}
	}

	errorLogger := func(reportErr, exception error, payload map[string]string) {
		logger.WithError(reportErr).Error("reporter.Report has failed")
	}

	reporter, err := newReporter(exporter, serviceName, environment, sha, ref, errorLogger)
	return reporter, err
}

// broken out for testing
func newReporter(
	exporter exceptions.Exporter,
	serviceName,
	environment,
	sha,
	ref string,
	errorLogger exceptions.ErrorLoggerFunc,
) (*exceptions.Reporter, error) {
	reporter, err := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithErrorLogger(errorLogger),
		exceptions.WithApplication(serviceName),
		exceptions.WithStacktraceFunc(NewRedactedStackTracer()),
		exceptions.WithCustomRedaction(redactSensitiveInfo),
		exceptions.WithValues(map[string]string{
			"deployed_to": environment,
			"release":     sha,
			"ref":         ref,
		}),
	)
	if err != nil {
		return nil, err
	}

	return reporter, nil
}

// NewRedactedStackTracer creates a stack tracer function that redacts sensitive information.
func NewRedactedStackTracer() func(err error) ([]exceptions.StackTrace, string) {
	pe := NewStackTracer()
	fn := func(err error) ([]exceptions.StackTrace, string) {
		stacktrace, rp := pe(err)
		// go-exceptions calls our custom redaction function _before_ calling
		// the stack tracer, so we need to manually apply redaction here
		for i, st := range stacktrace {
			if st.Type != "" {
				stacktrace[i].Type = redactSensitiveInfo(st.Type)
			}
			if st.Value != "" {
				stacktrace[i].Value = redactSensitiveInfo(st.Value)
			}
		}

		return stacktrace, rp
	}
	return fn
}

// NewStackTracer returns a stack tracer that uses any stack traces built into
// the error from the `stacktrace` package, otherwise it uses the default
// `pkgerrors` stack tracer.
func NewStackTracer() func(err error) ([]exceptions.StackTrace, string) {
	pe := pkgerrors.NewStackTracer()
	return func(err error) ([]exceptions.StackTrace, string) {
		stacks := goerrors.GetStacks(err)

		// If we have a stack trace in our error, use that to generate a stack trace
		var traces []exceptions.StackTrace
		if len(stacks) != 0 {
			traces = buildStackTraces(stacks, err.Error(), fmt.Sprintf("%T", err))
		} else {
			traces, _ = pe(err)
		}

		// Look for any custom defined rollup identifiers in our stack
		var rollupErr interface{ RollupInfo() string }
		if errors.As(err, &rollupErr) {
			return traces, rollupErr.RollupInfo()
		}

		// Fall back to using the error message as before
		return traces, redactRollupInfo(redactSensitiveInfo(err.Error()))
	}
}

func buildStackTraces(stacks []goerrors.StacktraceError, errorMessage, errorType string) []exceptions.StackTrace {
	exceptionStacks := make([]exceptions.StackTrace, len(stacks))
	for i, stack := range stacks {
		exceptionFrames := []exceptions.StackFrame{}
		for frame := range stack.Frames() {
			fileName := filepath.Base(frame.FileName)
			if gitRoot != "" {
				relPath, err := filepath.Rel(gitRoot, frame.FileName)
				if err == nil && !strings.HasPrefix(relPath, "..") {
					fileName = relPath
				}
			}

			exceptionFrames = append(exceptionFrames, exceptions.StackFrame{
				FileName:   fileName,
				AbsPath:    frame.FileName,
				LineNumber: fmt.Sprintf("%d", frame.LineNumber),
				Function:   frame.Function,
			})
		}

		// Sentry expects "oldest first" so we have to reverse our frames.
		slices.Reverse(exceptionFrames)

		exceptionStacks[i] = exceptions.StackTrace{
			Type:   errorType,
			Value:  errorMessage,
			Frames: exceptionFrames,
		}
	}

	return exceptionStacks
}

type replacer struct {
	placeholder string
	pattern     *regexp.Regexp
}

// Pre-compiled regex patterns for createFlexiblePattern and adaptPlaceholderToHostname
var (
	apiGithubComPattern         = regexp.MustCompile(`(?:^|[^a-zA-Z0-9.-])api\\\.github\\\.com(?:[^a-zA-Z0-9.-]|$)`)
	apiGithubComReplacer        = regexp.MustCompile(`(https://)api\\\.github\\\.com(/|$)`)
	apiGithubCopilotComPattern  = regexp.MustCompile(`(?:^|[^a-zA-Z0-9.-])api\\\.githubcopilot\\\.com(?:[^a-zA-Z0-9.-]|$)`)
	apiGithubCopilotComReplacer = regexp.MustCompile(`(https://)api\\\.githubcopilot\\\.com(/|$)`)

	// Pre-compiled patterns for adaptPlaceholderToHostname
	internalAPIPattern       = regexp.MustCompile(`^https://internal-api\.service\.[a-zA-Z0-9.\-_]+\.github\.net/`)
	internalAPIStampPattern  = regexp.MustCompile(`^https://internal-api\.service\.([a-zA-Z0-9.\-_]+)\.github\.net/`)
	internalPathPattern      = regexp.MustCompile(`/internal/`)
	tenantPathPattern        = regexp.MustCompile(`/[a-zA-Z0-9.\-_]+/(repos|repositories)/`)
	copilotAPIPattern        = regexp.MustCompile(`^https://copilot-api\.[a-zA-Z0-9.\-_]+\.ghe\.com/`)
	githubAPIReplacer        = regexp.MustCompile(`^https://api\.github\.com/`)
	githubCopilotAPIReplacer = regexp.MustCompile(`^https://api\.githubcopilot\.com/`)
)

// createFlexiblePattern enhances URL patterns to support parameterized hostnames.
// It replaces specific hostnames with a flexible pattern that matches both production and Proxima hostnames.
func createFlexiblePattern(originalPattern string) *regexp.Regexp {
	// Replace api.github.com with parameterized hostname pattern
	if apiGithubComPattern.MatchString(originalPattern) {
		parameterizedPattern := apiGithubComReplacer.ReplaceAllString(
			originalPattern,
			`${1}(?:api\.github\.com|internal-api\.service\.[a-zA-Z0-9.\-_]+\.github\.net)/(?:[a-zA-Z0-9.\-_]+/)?`,
		)
		return regexp.MustCompile(parameterizedPattern)
	}

	// Replace api.githubcopilot.com with parameterized hostname pattern
	if apiGithubCopilotComPattern.MatchString(originalPattern) {
		parameterizedPattern := apiGithubCopilotComReplacer.ReplaceAllString(
			originalPattern,
			`${1}(?:api\.githubcopilot\.com|copilot-api\.[a-zA-Z0-9.\-_]+\.ghe\.com)${2}`,
		)
		return regexp.MustCompile(parameterizedPattern)
	}

	return regexp.MustCompile(originalPattern)
}

var sensitiveInfoReplacers = []replacer{
	// Endpoint format using owner and repo names
	{"https://api.github.com/repos/:owner/:repo/issues/:number/reactions/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/issues/\d+/reactions/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/actions/runs/:id/cancel", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/actions/runs/\d+/cancel([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/actions/runs/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/actions/runs/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/actions/jobs/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/actions/jobs/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/collaborators/:user/permission", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/collaborators/[a-zA-Z0-9._-]+/permission([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/issues/:number/comments", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/issues/\d+/comments([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/issues/:number", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/issues/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/issues/comments/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/issues/comments/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/pulls/:number/comments/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/pulls/\d+/comments/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/pulls/:number", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/pulls/\d+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo/git/commits/:hash", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+/git/commits/[a-zA-Z0-9]+([^/]|$)`)},
	{"https://api.github.com/repos/:owner/:repo", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repos/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+([^/]|$)`)},

	// Alternate endpoint format using repository ID
	{"https://api.github.com/repositories/:repo/issues/:number/reactions/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/issues/\d+/reactions/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/actions/runs/:id/cancel", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/actions/runs/\d+/cancel([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/actions/runs/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/actions/runs/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/actions/jobs/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/actions/jobs/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/collaborators/:user/permission", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/collaborators/[a-zA-Z0-9._-]+/permission([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/issues/:number/comments", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/issues/\d+/comments([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/issues/:number", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/issues/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/issues/comments/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/issues/comments/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/pulls/:number/comments/:id", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/pulls/\d+/comments/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/pulls/:number", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/pulls/\d+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo/git/commits/:hash", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+/git/commits/[a-zA-Z0-9]+([^/]|$)`)},
	{"https://api.github.com/repositories/:repo", createFlexiblePattern(`(^|[^/])https://api\.github\.com/repositories/\d+([^/]|$)`)},

	// Other endpoints
	{"https://api.github.com/applications/:id/token", createFlexiblePattern(`(^|[^/])https://api\.github\.com/applications/[a-zA-Z0-9._-]+/token([^/]|$)`)},
	{"https://github.com/:owner/:repo.git", regexp.MustCompile(`(^|[^/])https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\.git([^/]|$)`)},
	{"https://github.com/:owner/:repo", regexp.MustCompile(`(^|[^/])https://github\.com/[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+([^/]|$)`)},
	{"https://api.githubcopilot.com/agents/sessions/:session", createFlexiblePattern(`(^|[^/])https://api\.githubcopilot\.com/agents/sessions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}([^/]|$)`)},
	{"copilot/<branch>", regexp.MustCompile(`\bcopilot/[a-zA-Z0-9-]+\b`)},

	// Redact branch names in validation error messages but don't overwrite already redacted ones
	{"branch '<branch>'", regexp.MustCompile(`\bbranch '[^'<>]*'`)},

	// Redact owner/repo references in error messages (e.g., "in repo owner/repo")
	{"repo <owner>/<repo>", regexp.MustCompile(`\brepo [a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+\b`)},

	{"<ip-address>", regexp.MustCompile(`(^|[^.\d])(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?([^.\d]|$)`)},
	{"<app>/<queue>/<job-id>:<cluster>:", regexp.MustCompile(`\b([a-z][a-z-]*)/([a-zA-Z][a-zA-Z-]*)/(\d+-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}):([a-z]+):`)},
}

// adaptPlaceholderToHostname adapts the placeholder hostname based on the matched URL hostname.
// It handles both Proxima internal API URLs and production GitHub API URLs, including tenant paths
func adaptPlaceholderToHostname(placeholder, matchedURL string) string {
	if internalAPIPattern.MatchString(matchedURL) {
		stampMatch := internalAPIStampPattern.FindStringSubmatch(matchedURL)
		if len(stampMatch) > 1 {
			stamp := stampMatch[1]

			if internalPathPattern.MatchString(matchedURL) {
				return githubAPIReplacer.ReplaceAllString(placeholder, "https://internal-api.service."+stamp+".github.net/internal/")
			}

			if tenantPathPattern.MatchString(matchedURL) {
				return githubAPIReplacer.ReplaceAllString(placeholder, "https://internal-api.service."+stamp+".github.net/<tenant>/")
			}
		}
	}

	if copilotAPIPattern.MatchString(matchedURL) {
		return githubCopilotAPIReplacer.ReplaceAllString(placeholder, "https://copilot-api.<tenant>.ghe.com/")
	}

	return placeholder
}

// redactSensitiveInfo redacts sensitive information from the error message.
func redactSensitiveInfo(val string) string {
	for _, r := range sensitiveInfoReplacers {
		val = r.pattern.ReplaceAllStringFunc(val, func(match string) string {
			submatches := r.pattern.FindStringSubmatch(match)
			if len(submatches) == 5 && strings.HasPrefix(r.placeholder, "<app>/<queue>/<job-id>") {
				// Preserve app and queue name
				return fmt.Sprintf("%s/%s/<job-id>:<cluster>:", submatches[1], submatches[2])
			}
			if len(submatches) >= 3 {
				// For anchored patterns: preserve boundaries, redact middle content
				content := match[len(submatches[1]) : len(match)-len(submatches[2])]
				placeholder := adaptPlaceholderToHostname(r.placeholder, content)
				return submatches[1] + placeholder + submatches[2]
			}
			// For simple patterns: redact entire match
			return adaptPlaceholderToHostname(r.placeholder, match)
		})
	}
	return val
}

var rollupReplacers = []replacer{
	{"<database-id>", regexp.MustCompile(`\d+-\d+-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`)},
	{"<request-id>", regexp.MustCompile(`[0-9A-Fa-f]{1,8}:[0-9A-Fa-f]{1,8}:[0-9A-Fa-f]{1,8}:[0-9A-Fa-f]{1,8}:[0-9A-Fa-f]{1,8}`)},
	{"<request-id>", regexp.MustCompile(`\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b`)},
	{"<retry-info>", regexp.MustCompile(`retried \d+ times \(total retry wait time: \d+ seconds\)`)},
	{"after <attempts>", regexp.MustCompile(`after \d+ attempts?`)},
	{"<datetime>", regexp.MustCompile(`\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z`)},
	{"timeout after <timeout>", regexp.MustCompile(`timeout after \d+(?:\.\d+)?s`)},
}

// redactRollupInfo redacts request-specific information from the rollup info.
// This ensures that request-specific information is not considered when grouping
// exceptions in Sentry. Unlike [redactSensitiveInfo], this function is not
// applied to the exception message itself, only the rollup used for grouping.
func redactRollupInfo(val string) string {
	for _, re := range rollupReplacers {
		val = re.pattern.ReplaceAllString(val, re.placeholder) // replace sensitive info with placeholders
	}

	return val
}
