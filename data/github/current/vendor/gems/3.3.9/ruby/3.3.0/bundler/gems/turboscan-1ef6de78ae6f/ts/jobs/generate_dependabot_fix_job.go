package jobs

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	ccf "github.com/github/turboscan/ts/cocofix"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
)

type GenerateDependabotFixJob struct {
	RequestId uint32
	RepoID    ts.RepositoryEID
	CommitOid ts.Sha
	Sarif     string
	FilePaths []string
}

var _ aqueduct.EnqueableJob = (*GenerateDependabotFixJob)(nil)

var processedMetric = "generate_dependabot_fix_job.processed"

func (p GenerateDependabotFixJob) Name() string {
	return "GenerateDependabotFixJob"
}

func (p GenerateDependabotFixJob) Queue() string {
	return "turboscan-generate-dependabot-fix"
}

func (p GenerateDependabotFixJob) GetRepositoryID() *ts.RepositoryEID {
	return &p.RepoID
}

func (p GenerateDependabotFixJob) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func (p GenerateDependabotFixJob) Perform(ctx context.Context, s *aqueduct.TSServices) error {
	ctx = appctx.With(ctx,
		kvp.Uint32("gh.request.id", p.RequestId),
		p.RepoID.AsKVP(),
		kvp.String("gh.commit.sha", string(p.CommitOid)),
		kvp.Uint8("gh.turboscan.retry_count", appctx.GetAqueductJobRetryCount(ctx)),
	)
	ctx = appctx.WithLogger(ctx, appctx.Logger(ctx).Named("generate_dependabot_fix_job"))

	if s == nil || s.SuggestedFixes == nil {
		return errors.New("missing required services")
	}

	err := p.perform(ctx, s.SuggestedFixes)

	if err != nil {
		var te *ccf.TransientError
		transient := "false"
		if errors.As(err, &te) {
			transient = "true"
		}

		// handle non-retriable error
		var ne *ccf.NonRetriableError
		if errors.As(err, &ne) {
			appctx.Stats(ctx).Counter(processedMetric, stats.Tags{"transient": transient, "error": "false"}, 1)
			p.publishErrorResult(ctx, s.SuggestedFixes.DependabotAutofixResultPublisher)

			return nil
		}

		retryCount := appctx.GetAqueductJobRetryCount(ctx)
		if retryCount < aqueduct.MaxRetryCount {
			payload := map[string]string{
				"repository_id": fmt.Sprintf("%d", p.RepoID),
				"commit_oid":    p.CommitOid.String(),
				"request_id":    fmt.Sprintf("%d", p.RequestId),
			}
			appctx.Report(ctx, err, payload)
			appctx.Stats(ctx).Counter(processedMetric, stats.Tags{"transient": transient, "error": "true"}, 1)
		} else {
			payload := map[string]string{
				"repository_id": fmt.Sprintf("%d", p.RepoID),
				"commit_oid":    p.CommitOid.String(),
				"request_id":    fmt.Sprintf("%d", p.RequestId),
			}
			appctx.Report(ctx, errors.Wrap(err, "job(GenerateDependabotFixJob) retry limit exceeded"), payload)
			appctx.Stats(ctx).Counter(processedMetric, stats.Tags{"transient": transient, "error": "true", "noretry": "true"}, 1)

			p.publishErrorResult(ctx, s.SuggestedFixes.DependabotAutofixResultPublisher)
		}
	}

	return err
}

func (p GenerateDependabotFixJob) perform(ctx context.Context, sf *suggestedfixes.SuggestedFixes) error {
	if !flipper.HasDependabotAutofix(ctx, p.RepoID) {
		return &ccf.NonRetriableError{}
	}

	res, err := sf.FixGenerator.GenerateDependabotFix(ctx, p.Sarif, p.FilePaths, sf.DownloadFunc(p.RepoID, p.CommitOid), p.RepoID, sf.ProximaEnv)
	if err != nil {
		return errors.Wrap(err, "failed to generate a suggested fix for dependabot")
	}

	// publish event
	err = sf.DependabotAutofixResultPublisher.PublishDependabotAutofixResult(ctx, p.serializeHydroEvent(res))
	if err != nil {
		return errors.Wrap(err, "failed to publish DependabotAutofixResult event after generating fix")
	}

	appctx.Stats(ctx).Counter(processedMetric, stats.Tags{"error": "false"}, 1)
	return nil
}

func (p GenerateDependabotFixJob) publishErrorResult(ctx context.Context, publisher suggestedfixes.DependabotAutofixResultPublisher) {
	err := publisher.PublishDependabotAutofixResult(ctx, &tshydro.DependabotAutofixResult{
		RequestId: p.RequestId,
		State:     tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_ERROR,
	})
	if err != nil {
		payload := map[string]string{
			"repository_id": fmt.Sprintf("%d", p.RepoID),
			"commit_oid":    p.CommitOid.String(),
			"request_id":    fmt.Sprintf("%d", p.RequestId),
		}
		appctx.Report(ctx, errors.Wrap(err, "failed to publish DependabotAutofixResult event after retry limit exceeded"), payload)
	}
}

func (p GenerateDependabotFixJob) serializeHydroEvent(res ts.GenerateFixResult) *tshydro.DependabotAutofixResult {
	hydroEvent := &tshydro.DependabotAutofixResult{
		RequestId: p.RequestId,
	}

	if res.SuggestedFixAlertState == ts.SuggestedFixAlertStateValid {
		hydroEvent.State = tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_VALID
	} else {
		hydroEvent.State = tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_INVALID
	}

	if res.SuggestedFix != nil {
		hydroEvent.AiModel = res.SuggestedFix.AiModel
		hydroEvent.AiVersion = res.SuggestedFix.AiVersion

		var files []*tshydro.DependabotAutofixResult_SuggestedFixFile
		for _, f := range res.SuggestedFix.Files {
			f := &tshydro.DependabotAutofixResult_SuggestedFixFile{
				FilePath:    f.FilePath,
				DiffContent: f.FormatDiff(),
			}
			files = append(files, f)
		}
		sfHydro := &tshydro.DependabotAutofixResult_SuggestedFix{
			Files:       files,
			Description: res.SuggestedFix.Description,
		}
		if res.SuggestedFix.DependencyMetadata != nil {
			var dmHydro []*tshydro.DependabotAutofixResult_DependencyMetadata

			for _, m := range res.SuggestedFix.DependencyMetadata {
				dh := &tshydro.DependabotAutofixResult_DependencyMetadata{
					Name:    m.Name,
					Version: m.Version,
				}
				dmHydro = append(dmHydro, dh)
			}
			sfHydro.DependencyMetadata = dmHydro
		}
		hydroEvent.SuggestedFix = sfHydro
	}

	return hydroEvent
}
