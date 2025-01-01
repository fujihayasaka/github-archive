package api

import (
	"context"
	"strconv"
	"time"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/alerts"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fix"
	"github.com/github/codeml-autofix/go/v2/pkg/autofix/fixdata"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

// This file contains telemetry-related functions for fix suggestions.
// It collects various metrics about the fix suggestion process, including
// the number of edits, assessment outcomes, problems encountered, and
// dependency metadata.

// TODO move all telemeretry-related code to a separate package
// to keep the API package cleaner. And create easier utility to use across the codebase to log and record telemetry.
type fixTelemetryMetadata struct {
	editCount           int
	assessmentOutcome   string
	problemCount        int
	dependencyCount     int
	hasDependencyIssues bool
	hasVulnerabilities  bool

	problemTypes map[fixdata.ProblemKind]int

	ecosystemCounts map[string]int
}

func collectFixTelemetry(fixSuggestion *fix.FixSuggestion) fixTelemetryMetadata {
	telemetry := fixTelemetryMetadata{ //nolint:exhaustruct
		editCount:         len(fixSuggestion.Edits),
		assessmentOutcome: string(fixSuggestion.Assessment.Outcome),
		problemCount:      len(fixSuggestion.Assessment.Problems),
		dependencyCount:   len(fixSuggestion.DependencyMetadata),
		problemTypes:      make(map[fixdata.ProblemKind]int),
		ecosystemCounts:   make(map[string]int),
	}

	for _, problem := range fixSuggestion.Assessment.Problems {
		telemetry.problemTypes[problem.Kind]++

		switch problem.Kind {
		case fixdata.ProblemKind_MISSING_DEPENDENCY:
			telemetry.hasDependencyIssues = true
		case fixdata.ProblemKind_VULNERABLE_DEPENDENCY:
			telemetry.hasVulnerabilities = true
		}
	}

	for _, dep := range fixSuggestion.DependencyMetadata {
		if dep.Ecosystem != "" {
			telemetry.ecosystemCounts[dep.Ecosystem]++
		}
	}

	return telemetry
}

func recordFixError(ctx context.Context, fixErr *fix.FixError) {
	enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.error_type",
		stats.Tags{"type": fixErr.Err.Type()}, 1)
}

func logFixSuccess(ctx context.Context, telemetry fixTelemetryMetadata, previousAttemptsCount int, alert alerts.Alert) {
	logFields := []kvp.Field{
		kvp.Int("gh.autofix.num_edits", telemetry.editCount),
		kvp.String("gh.autofix.assessment_outcome", telemetry.assessmentOutcome),
		kvp.Int("gh.autofix.problem_count", telemetry.problemCount),
		kvp.Int("gh.autofix.dependency_count", telemetry.dependencyCount),
		kvp.Bool("gh.autofix.has_dependency_issues", telemetry.hasDependencyIssues),
		kvp.Bool("gh.autofix.has_vulnerability_issues", telemetry.hasVulnerabilities),
		kvp.Int("gh.autofix.previous_attempts_count", previousAttemptsCount),
		kvp.String("gh.autofix.rule", alert.Rule.ID),
		kvp.String("gh.autofix.language", string(alert.Language)),
	}

	enhancedctx.Logger(ctx).Info("Generated fix suggestion", logFields...)
}

func logFixError(ctx context.Context, previousAttemptsCount int, alert alerts.Alert, fixErr *fix.FixError) {
	logFields := []kvp.Field{
		kvp.Int("gh.autofix.previous_attempts_count", previousAttemptsCount),
		kvp.String("gh.autofix.rule", alert.Rule.ID),
		kvp.String("gh.autofix.language", string(alert.Language)),
	}

	enhancedctx.Logger(ctx).WithError(fixErr.Err).Error("Failed to generate fix suggestion", logFields...)
}

func logFixProblems(ctx context.Context, problems []fixdata.Problem) {
	for i, problem := range problems {
		enhancedctx.Logger(ctx).Info(
			"Assessment problem",
			kvp.Int("gh.autofix.problem_index", i),
			kvp.String("gh.autofix.problem_kind", string(problem.Kind)),
			kvp.String("gh.autofix.problem_description", problem.Description),
		)
	}
}

func recordFixStats(ctx context.Context, telemetry fixTelemetryMetadata) {
	enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.outcome",
		stats.Tags{
			"outcome":      telemetry.assessmentOutcome,
			"has_problems": strconv.FormatBool(telemetry.problemCount > 0),
		}, 1)

	for problemKind, count := range telemetry.problemTypes {
		enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.problem_kind",
			stats.Tags{"kind": string(problemKind)}, int64(count))
	}

	if telemetry.dependencyCount > 0 {
		enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.has_dependencies",
			stats.Tags{
				"has_issues":          strconv.FormatBool(telemetry.hasDependencyIssues),
				"has_vulnerabilities": strconv.FormatBool(telemetry.hasVulnerabilities),
			}, 1)

		enhancedctx.Statter(ctx).Distribution("fix_suggestion_generation.dependency_count",
			nil, float64(telemetry.dependencyCount))

		for ecosystem, count := range telemetry.ecosystemCounts {
			enhancedctx.Statter(ctx).Counter("fix_suggestion_generation.dependency_ecosystem",
				stats.Tags{"ecosystem": ecosystem}, int64(count))
		}
	}
}

func recordFixDuration(ctx context.Context, duration time.Duration, hasError bool) {
	enhancedctx.Statter(ctx).DistributionMs("fix_suggestion_generation.duration",
		stats.Tags{"fix_error": strconv.FormatBool(hasError)},
		duration)
}

func recordTotalDuration(ctx context.Context, duration time.Duration) {
	enhancedctx.Statter(ctx).DistributionMs("alerts_fix_generation.duration", nil, duration)
}
