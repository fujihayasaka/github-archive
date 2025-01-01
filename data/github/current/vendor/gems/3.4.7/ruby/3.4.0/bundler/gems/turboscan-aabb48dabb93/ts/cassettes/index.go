package cassettes

import (
	"database/sql"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func (session *Session) IndexWithRepoMetadata(t *testing.T, repositoryID uint64, ownerID uint64, defaultRef string, visibility string, codeScanningEnabled bool) {
	t.Helper()
	repo := &ts.Repository{
		RepositoryID:        ts.RepositoryEID(repositoryID),
		OwnerID:             ts.OwnerEID(ownerID),
		CodeScanningEnabled: codeScanningEnabled,
		DefaultRef:          []byte(defaultRef),
		SourceUpdatedAt:     sqltime.Now(),
		Visibility:          sql.NullString{String: visibility, Valid: true},
	}
	err := session.repositoryService.Update(session.ctx, repo)
	require.NoError(t, err)
	loader := session.alertService.NewLoader(repo)
	err = loader.BatchedLoad(session.ctx, func(alerts []*ts.LogicalAlert) error {
		docs, err := ts.SearchDocumentsFromAlerts(repo, alerts)
		if err != nil {
			return err
		}
		return session.search.IndexDocuments(session.ctx, ts.Index_OrgLevel, docs)
	})
	require.NoError(t, err)
	require.NoError(t, session.search.Refresh(session.ctx, ts.Index_OrgLevel))
}

func (session *Session) RefreshES(t *testing.T) {
	t.Helper()
	require.NoError(t, session.search.Refresh(session.ctx, ts.Index_OrgLevel))
}
