// Package cocofix defines cocofix types, parser and mapping with alerts
package cocofix

import (
	"context"
	_ "embed"
	"fmt"
	"strconv"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
)

const AIModel = "capi-prod-4o"

// buildGenerateFixResponse builds GenerateFixResult from CocofixOutput
func (c *CocofixRunner) buildGenerateFixResponse(ctx context.Context, fix Output, repoID ts.RepositoryEID, sums map[string]ts.Sha1Checksum, integration ts.CapiIntegrationType, isCampaign bool) (ts.GenerateFixResult, error) {
	tags := stats.Tags{
		"outcome_kind":       fix.Outcome.Kind,
		"outcome_assessment": fix.Outcome.Assessment.Outcome,
		"outcome_transient":  strconv.FormatBool(fix.Outcome.Transient),
		"outcome_severity":   string(fix.Outcome.Severity),
		"integration":        integration.String(),
	}
	// Add tag to indicate if the fix is for a security campaign
	if isCampaign {
		tags["is_campaign"] = "true"
	} else {
		tags["is_campaign"] = "false"
	}

	appctx.Stats(ctx).Counter("cocofix_runner.response.fixes", tags, 1)

	filePath := fix.Alert.Location.Path
	ruleId := fix.Alert.RuleId

	// Kind can be fix|error
	if fix.Outcome.Kind == "error" {
		appctx.Logger(ctx).Info("outcome kind is an error",
			kvp.String("rule_id", ruleId),
			kvp.String("file_path", filePath),
			kvp.String("error", fix.Outcome.Error),
			kvp.String("severity", string(fix.Outcome.Severity)),
			kvp.String("description", fix.Outcome.Description),
			kvp.Bool("transient", fix.Outcome.Transient),
			kvp.String("sarifInput", c.sarifInput),
			kvp.String("integration", integration.String()),
		)

		c.PublishErrorOutcome(ctx, &fix, repoID)

		if fix.Outcome.Transient {
			// we should retry any transient error
			return ts.GenerateFixResult{}, &TransientError{
				Err: errors.Errorf("Transient failure, err: %s, severity: %s", fix.Outcome.Error, fix.Outcome.Severity),
			}
		}

		// fallback to NonRetriableError
		return ts.GenerateFixResult{}, &NonRetriableError{errors.Errorf("Non transient failure, err: %s, severity: %s", fix.Outcome.Error, fix.Outcome.Severity)}
	}

	// kind is fix
	// check outcome, it can be valid|invalid

	if fix.Outcome.Assessment.Outcome == "invalid" {
		problems := []string{}
		for _, p := range fix.Outcome.Assessment.Problems {
			// format p.Kind and p.Description into a string
			problems = append(problems, fmt.Sprintf("%s: %s", p.Kind, p.Description))
		}

		appctx.Logger(ctx).Info("invalid assessment outcome",
			kvp.String("rule_id", ruleId),
			kvp.String("file_path", filePath),
			kvp.String("outcome", fix.Outcome.Assessment.Outcome),
			kvp.Strings("problems", problems),
			kvp.String("integration", integration.String()),
		)

		c.PublishInvalidOutcome(ctx, &fix, repoID)

		return ts.GenerateFixResult{
			SuggestedFixAlertState: ts.SuggestedFixAlertStateInvalid,
		}, nil
	}

	// this is a valid fix
	suggestedFix := &ts.SuggestedFix{
		RepositoryID: repoID,
		Description:  fix.Outcome.Details.FixDescription,
		AiVersion:    getAIVersion(),
		AiModel:      AIModel,
	}
	if len(fix.Outcome.Details.DependencyMetadata) > 0 {
		suggestedFix.DependencyMetadata = make([]ts.SuggestedFixDependency, len(fix.Outcome.Details.DependencyMetadata))
		for i, metadata := range fix.Outcome.Details.DependencyMetadata {
			suggestedFix.DependencyMetadata[i] = ts.SuggestedFixDependency{
				Name:        metadata.Name,
				Version:     metadata.Version,
				Description: metadata.Description,
				Url:         metadata.Url,
				Ecosystem:   metadata.Ecosystem,
				IsMalicious: metadata.IsMalicious,
				Advisories:  make([]ts.SuggestedFixAdvisory, len(metadata.Advisories)),
			}

			for j, advisory := range metadata.Advisories {
				suggestedFix.DependencyMetadata[i].Advisories[j] = ts.SuggestedFixAdvisory{
					Id:          advisory.Id,
					HtmlUrl:     advisory.HtmlUrl,
					Summmary:    advisory.Summmary,
					Description: advisory.Description,
					Severity:    ts.SuggestedFixAdvisorySeverity(advisory.Severity),
				}
			}
		}
	}

	for _, diff := range fix.Outcome.Diffs {
		sum, ok := sums[diff.Path]
		// We check the checksums here to avoid sending a checksum of an empty file
		// However if there is no checksums to check we just send the empty checksum
		if len(sums) > 0 && !ok {
			appctx.Logger(ctx).Info("no checksum found for file",
				kvp.String("file", diff.Path),
				kvp.String("integration", integration.String()),
			)
			continue
		}
		file := &ts.SuggestedFixFile{
			RepositoryID: repoID,
			DiffContent:  []byte(diff.Diff),
			FilePath:     diff.Path,
			FilePathHash: ts.BuildFilePathHash(diff.Path),
			FileChecksum: sum,
		}
		suggestedFix.Files = append(suggestedFix.Files, file)
	}

	return ts.GenerateFixResult{
		SuggestedFixAlertState: ts.SuggestedFixAlertStateValid,
		SuggestedFix:           suggestedFix,
	}, nil
}
