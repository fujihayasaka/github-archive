package db_test

import (
	"context"
	"database/sql"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_RepositoryStateChanged(t *testing.T) {
	tests := []struct {
		name                string
		f                   func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip)
		expectedStateChange bool
	}{
		{
			name: "no state change when license name is the same in database and API",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.LicenseName = sql.NullString{String: "MIT License", Valid: true}
				apir.LicenseName = "MIT License"
			},
			expectedStateChange: false,
		},
		{
			name: "no state change when non-NULL empty license name in database and blank from API",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.LicenseName = sql.NullString{String: "", Valid: true}
				apir.LicenseName = ""
			},
			expectedStateChange: false,
		},
		{
			name: "state change when NULL license name in database and blank from API",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.LicenseName = sql.NullString{}
				apir.LicenseName = ""
			},
			expectedStateChange: true,
		},
		{
			name: "state change when license name differs between database and API",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.LicenseName = sql.NullString{String: "GNU GPL", Valid: true}
				apir.LicenseName = "AGPL"
			},
			expectedStateChange: true,
		},
		{
			name: "state change when repo_seq_no in database is the default zero value",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.RepoSeqNo = sql.NullInt64{} // Indicates the default zero value.
				apir.RepoSeqNo = 1
			},
			expectedStateChange: true,
		},
		{
			name: "state change when repo_seq_no in database is earlier than the API's repo sequence number",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.RepoSeqNo = sql.NullInt64{Int64: 2, Valid: true}
				apir.RepoSeqNo = 3
			},
			expectedStateChange: true,
		},
		{
			name: "no state change when repo_seq_no in database is greater than or equal to the API's repo sequence number",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.RepoSeqNo = sql.NullInt64{Int64: 2, Valid: true}
				apir.RepoSeqNo = 2
			},
			expectedStateChange: false,
		},
		{
			name: "state change when owner login differs between database and API",
			f: func(dbr *db.Repository, apir *github.Repository, refTip *gitaccess.RefTip) {
				dbr.OwnerLogin = "old_login"
				apir.OwnerLogin = "new_login"
			},
			expectedStateChange: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			refTip := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
			dbr := helpers.Repositories(t, 1)[0]
			dbr.CommitOID = refTip.CommitOID.Bytes()
			apir := helpers.GitHubRepositoryFromRepository(t, dbr)

			tt.f(dbr, apir, refTip)

			require.Equal(t, tt.expectedStateChange, db.RepositoryStateChanged(ctx, dbr, apir, refTip))
		})
	}
}
