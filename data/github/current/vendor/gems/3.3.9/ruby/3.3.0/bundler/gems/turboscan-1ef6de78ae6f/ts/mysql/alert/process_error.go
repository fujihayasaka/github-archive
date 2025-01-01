package alert

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/pkg/errors"
)

// LogProcessError writes a new instance of ProcessError to the database
func (s *Service) LogProcessError(ctx context.Context, pe *ts.ProcessError) error {
	appctx.Logger(ctx).Info("Error saved as Unrecoverable Analysis Error", kvp.String("gh.turboscan.error", pe.Message))

	var tool ts.ToolName = "Unknown"
	if pe.Analysis != nil && pe.Analysis.Tool != nil {
		tool = pe.Analysis.Tool.CanonicalName
	}
	appctx.Stats(ctx).Counter("process_error", stats.Tags{"tool": tool.String()}, 1)

	// We're truncating the error message to prevent the db errors when saving too large field.
	if len(pe.Message) > 4096 {
		pe.Message = ts.Truncate(pe.Message, 4096)
	}

	err := s.db.Create(&pe).Error
	if err != nil {
		return errors.Wrap(err, "")
	}
	return nil
}

// ProcessErrorsForSarifId returns all ProcessErrors for a given repoId and sarifId (both must match)
func (s *Service) ProcessErrorsForSarifId(repoID ts.RepositoryEID, sarifID ts.SarifID) ([]*ts.ProcessError, error) {
	var pErrors []*ts.ProcessError
	err := s.db.Where("repository_id = ?", repoID).
		Where("sarif_id = ?", sarifID).
		Limit(100).
		Order("updated_at desc").
		Find(&pErrors).
		Error

	if err != nil {
		return nil, err
	}

	return pErrors, nil
}
