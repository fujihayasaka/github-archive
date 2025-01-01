package root

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/pkg/errors"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/github/turboscan/ts/mocks"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func validTime(time sqltime.Time) sql.NullTime {
	return sql.NullTime{Time: time.Time, Valid: true}
}

func setUpEnvironment(t *testing.T) (
	db *gorm.DB,
	mockTwirpAPI *mocks.MockRepositoryAPI,
	mockInternalAPI *mocks.MockReposAuditsGetter,
	mockRepoDeleter *mocks.MockRepoDeleter) {
	t.Helper()
	db = dbtest.RequireConnection(t)
	mockCtrl := gomock.NewController(t)
	mockTwirpAPI = mocks.NewMockRepositoryAPI(mockCtrl)
	mockInternalAPI = mocks.NewMockReposAuditsGetter(mockCtrl)
	mockRepoDeleter = mocks.NewMockRepoDeleter(mockCtrl)

	es = elasticsearch.SetUpTestElasticSearchService(t)
	as = alert.TestService(db)

	rs = repository.NewService(db)
	repoTwirpAPI = mockTwirpAPI
	repoInternalAPI = mockInternalAPI
	repoDeleter = mockRepoDeleter
	start = time.Now()
	return
}

func TestIndexActive(t *testing.T) {
	db, mockAPI, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		targets:   []string{TargetActive},
		horizon:   24,
		repoStep:  100,
		alertStep: 100,
	}
	defaultRef := []byte("refs/heads/main")
	updatedAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	now := sqltime.Now()
	rule := &ts.Rule{
		Tool: &ts.Tool{
			CanonicalName: ts.ToolName("tool"),
			GUID:          "tool",
		},
	}

	// Repo1 has 1 recent alert, 1 old alert and updated metadata
	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: updatedAt, DefaultRef: defaultRef}
	alert11 := &ts.LogicalAlert{ID: 11, Number: 1, RepositoryID: 1, StableAlertIdentifier: []byte("11"), BaseModel: ts.BaseModel{UpdatedAt: now}, Rule: rule}
	alert12 := &ts.LogicalAlert{ID: 12, Number: 2, RepositoryID: 1, StableAlertIdentifier: []byte("12"), BaseModel: ts.BaseModel{UpdatedAt: updatedAt}, Rule: rule}
	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, alert11)
	dbtest.RequireCreate(t, db, alert12)
	repo1.OwnerID = 11

	// Repo2 has 1 recent alert, 1 old alert
	repo2 := &ts.Repository{RepositoryID: 2, OwnerID: 1, SourceUpdatedAt: updatedAt, DefaultRef: defaultRef}
	alert21 := &ts.LogicalAlert{ID: 21, Number: 1, RepositoryID: 2, StableAlertIdentifier: []byte("21"), BaseModel: ts.BaseModel{UpdatedAt: updatedAt}, Rule: rule}
	alert22 := &ts.LogicalAlert{ID: 22, Number: 2, RepositoryID: 2, StableAlertIdentifier: []byte("22"), BaseModel: ts.BaseModel{UpdatedAt: now}, Rule: rule}
	dbtest.RequireCreate(t, db, repo2)
	dbtest.RequireCreate(t, db, alert21)
	dbtest.RequireCreate(t, db, alert22)

	// Repo3 has an old alert
	repo3 := &ts.Repository{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: updatedAt, DefaultRef: defaultRef}
	alert3 := &ts.LogicalAlert{ID: 3, RepositoryID: 3, StableAlertIdentifier: []byte("3"), BaseModel: ts.BaseModel{UpdatedAt: updatedAt}, Rule: rule}
	dbtest.RequireCreate(t, db, repo3)
	dbtest.RequireCreate(t, db, alert3)

	// Repo4 has a new alert but had a full reindex after the update so it should not be indexed
	oneHourAgo := now.Add(-time.Hour)
	twoHoursAgo := sqltime.Time{Time: oneHourAgo.Add(-time.Hour)}
	repo4 := &ts.Repository{RepositoryID: 4, OwnerID: 1, SourceUpdatedAt: updatedAt, DefaultRef: defaultRef, LastIndexedAt: sql.NullTime{Valid: true, Time: oneHourAgo}}
	alert4 := &ts.LogicalAlert{ID: 4, Number: 1, RepositoryID: 4, StableAlertIdentifier: []byte("4"), BaseModel: ts.BaseModel{UpdatedAt: twoHoursAgo}, Rule: rule}
	dbtest.RequireCreate(t, db, repo4)
	dbtest.RequireCreate(t, db, alert4)
	repo4.LastIndexedAt = sql.NullTime{} // This is not returned from the API

	// We only expect to fetch metadata for repo1 and repo2 (i.e. the active ones)
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{1, 2, 4}).Return([]*ts.Repository{repo1, repo2, repo4}, nil)

	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Repos repo1, repo2 and repo4 should have been updated
	require.Equal(t, uint(3), totalUpdated)

	// The alerts that should have been indexed are: 11, 12 and 22
	docs, err := es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(3), docs)
}

func TestIndexOldest(t *testing.T) {
	db, mockAPI, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		targets:   []string{TargetOldest},
		horizon:   72,
		repoStep:  100,
		alertStep: 100,
	}
	defaultRef := []byte("refs/heads/main")
	now := sqltime.Now()
	sixDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -6)}
	twoDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -2)}

	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: sixDaysAgo, LastIndexedAt: validTime(sixDaysAgo), DefaultRef: defaultRef}
	repo2 := &ts.Repository{RepositoryID: 2, OwnerID: 1, SourceUpdatedAt: twoDaysAgo, LastIndexedAt: validTime(twoDaysAgo), DefaultRef: defaultRef}
	repo3 := &ts.Repository{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: twoDaysAgo, LastIndexedAt: validTime(now), DefaultRef: defaultRef}

	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, repo2)
	dbtest.RequireCreate(t, db, repo3)

	// repo1 is the only one that was indexed outside the cutoff period, so we expect it should be returned
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{repo1.RepositoryID}).Return([]*ts.Repository{repo1}, nil)

	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(1), totalUpdated)

	// Running the job again will not update anything
	err = runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(0), totalUpdated)

	// Reducing the horizon would update repo2
	args.horizon = 24
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{repo2.RepositoryID}).Return([]*ts.Repository{repo2}, nil)

	err = runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(1), totalUpdated)

}

func TestRepoCleanup(t *testing.T) {
	db, _, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		repoCleanup: true,
		repoStep:    100,
		alertStep:   100,
	}
	defaultRef := []byte("refs/heads/main")
	createdAt := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)

	// Repo1 has both an analysis and metadata
	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: createdAt, DefaultRef: defaultRef, BaseModel: ts.BaseModel{CreatedAt: createdAt}}
	a1 := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: []byte("refs/heads/main")}
	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, a1)

	// Repo2 has metadata, but no analyses
	repo2 := &ts.Repository{RepositoryID: 2, OwnerID: 1, SourceUpdatedAt: createdAt, DefaultRef: defaultRef, BaseModel: ts.BaseModel{CreatedAt: createdAt}}
	dbtest.RequireCreate(t, db, repo2)

	// Repo3 has an analysis, but no metadata
	repo3 := &ts.Repository{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: createdAt, DefaultRef: defaultRef, BaseModel: ts.BaseModel{CreatedAt: createdAt}}
	a3 := &ts.Analysis{ID: 3, RepositoryID: 3, SourceRepositoryID: 3, Ref: []byte("refs/heads/main")}
	dbtest.RequireCreate(t, db, a3)

	// One repo should have been cleaned up
	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(1), totalUpdated)

	// repo1 should not have been deleted
	r, err := rs.Find(ctx, repo1.RepositoryID)
	require.NoError(t, err)
	require.NotNil(t, r)

	// repo2 should have been deleted
	r, err = rs.Find(ctx, repo2.RepositoryID)
	require.NoError(t, err)
	require.Nil(t, r)

	// repo3 should still be missing (since we didn't opt for any update targets)
	r, err = rs.Find(ctx, repo3.RepositoryID)
	require.NoError(t, err)
	require.Nil(t, r)
}

func TestDeletedRepoCleanup(t *testing.T) {
	db, _, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		deletedRepoCleanup: true,
		deadline:           5,
		horizon:            24,
		repoStep:           100,
		alertStep:          100,
	}

	// Check index is empty to begin with
	docs, err := es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(0), docs)

	err = es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "1",
				AlertID:         43,
				FullDescription: "XSS is really bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         44,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			},
			{
				RepositoryID:    "3",
				AlertID:         45,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			},
		},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Check index now has the 4 (search) documents
	docs, err = es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(4), docs)

	// Meanwhile repos get deleted
	aWhileAgo := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	now := sqltime.Now()
	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: ts.RepositoryEID(1), DeleteFinishedAt: &aWhileAgo})
	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: ts.RepositoryEID(2), DeleteFinishedAt: &now})
	dbtest.RequireCreate(t, db, &ts.DeletedRepository{RepositoryID: ts.RepositoryEID(3), DeleteFinishedAt: &aWhileAgo})

	err = runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(2), totalUpdated) // Detected 2 deleted repos

	// Check index which should only have the single alert document from repo 2 left (because of the 24h horizon/cutoff)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))
	docs, err = es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(1), docs)
}

func TestMultipleTargets(t *testing.T) {
	db, mockAPI, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		targets:   []string{TargetActive, TargetOldest, TargetRepo},
		horizon:   72,
		repoID:    5,
		repoStep:  100,
		alertStep: 100,
	}
	defaultRef := []byte("refs/heads/main")
	twoYearsAgo := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	oneYearAgo := sqltime.Date(2021, time.February, 16, 0, 0, 0, 0, time.UTC)
	now := sqltime.Now()

	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: twoYearsAgo, LastIndexedAt: validTime(twoYearsAgo), DefaultRef: defaultRef}
	repo2 := &ts.Repository{RepositoryID: 2, OwnerID: 1, SourceUpdatedAt: oneYearAgo, LastIndexedAt: validTime(oneYearAgo), DefaultRef: defaultRef}
	repo3 := &ts.Repository{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: oneYearAgo, LastIndexedAt: validTime(oneYearAgo), DefaultRef: defaultRef}
	repo4 := &ts.Repository{RepositoryID: 4, OwnerID: 1, SourceUpdatedAt: now, LastIndexedAt: validTime(now), DefaultRef: defaultRef}
	repo5 := &ts.Repository{RepositoryID: 5, OwnerID: 1, SourceUpdatedAt: now, LastIndexedAt: validTime(now), DefaultRef: defaultRef}

	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, &ts.Analysis{RepositoryID: 1, SourceRepositoryID: 1, Ref: []byte("refs/heads/main")})
	dbtest.RequireCreate(t, db, repo2)
	dbtest.RequireCreate(t, db, repo3)
	dbtest.RequireCreate(t, db, repo4)
	dbtest.RequireCreate(t, db, &ts.LogicalAlert{RepositoryID: 4, StableAlertIdentifier: []byte("alert1"), BaseModel: ts.BaseModel{UpdatedAt: now}})
	dbtest.RequireCreate(t, db, repo5)

	// active check should return repo4
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{4}).Return([]*ts.Repository{repo4}, nil)

	// oldest check should return repo1, repo2 and repo3
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{1, 2, 3}).Return([]*ts.Repository{repo1, repo2, repo3}, nil)

	// repoID check should return repo5
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{5}).Return([]*ts.Repository{repo5}, nil)

	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(5), totalUpdated)
}

func TestDeadline(t *testing.T) {
	db, mockAPI, _, _ := setUpEnvironment(t)
	ctx := context.Background()

	args := &arguments{
		targets:   []string{TargetOldest},
		deadline:  50,
		repoStep:  100,
		alertStep: 100,
	}

	yesterday := sqltime.Time{Time: time.Now().Add(-24 * time.Hour)}
	defaultRef := []byte("refs/heads/main")
	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: yesterday, DefaultRef: defaultRef}
	repo2 := &ts.Repository{RepositoryID: 2, OwnerID: 1, SourceUpdatedAt: yesterday, DefaultRef: defaultRef}
	repo3 := &ts.Repository{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: yesterday, DefaultRef: defaultRef}

	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, repo2)
	dbtest.RequireCreate(t, db, repo3)

	// set start time to 1h ago
	start = time.Now().Add(-1 * time.Hour)
	mockAPI.EXPECT().GetRepositories(gomock.Any(), []ts.RepositoryEID{1, 2, 3}).Return([]*ts.Repository{repo1, repo2, repo3}, nil)

	err := runRepoIndexer(ctx, args)
	require.Error(t, err)
	require.ErrorIs(t, err, ErrDeadlineExceeded)
}

func TestSkipRepoSync(t *testing.T) {
	db, mockTwripReposAPI, mockReposInternalAPI, mockReposDeleter := setUpEnvironment(t)
	ctx := context.Background()

	repoTwirpAPI, repoInternalAPI = &skipRepoSyncAPI{}, &skipRepoSyncAPI{}

	args := &arguments{
		skipRepoSync: true,
		targets:      []string{TargetOldest},
		repoStep:     100,
		alertStep:    100,
	}
	defaultRef := []byte("refs/heads/main")
	now := sqltime.Now()
	sixDaysAgo := sqltime.Time{Time: now.AddDate(0, 0, -6)}

	rule := &ts.Rule{
		Tool: &ts.Tool{
			CanonicalName: ts.ToolName("tool"),
			GUID:          "tool",
		},
	}
	repo1 := &ts.Repository{RepositoryID: 1, OwnerID: 1, SourceUpdatedAt: sixDaysAgo, DefaultRef: defaultRef}
	possiblyDeletedRepo := &ts.Repository{RepositoryID: 2, SourceUpdatedAt: sixDaysAgo, DefaultRef: defaultRef}
	alert11 := &ts.LogicalAlert{ID: 11, Number: 1, RepositoryID: 1, StableAlertIdentifier: []byte("11"), BaseModel: ts.BaseModel{UpdatedAt: now}, Rule: rule}
	alert12 := &ts.LogicalAlert{ID: 12, Number: 2, RepositoryID: 1, StableAlertIdentifier: []byte("12"), BaseModel: ts.BaseModel{UpdatedAt: now}, Rule: rule}
	dbtest.RequireCreate(t, db, repo1)
	dbtest.RequireCreate(t, db, alert11)
	dbtest.RequireCreate(t, db, alert12)
	dbtest.RequireCreate(t, db, possiblyDeletedRepo)

	// Check index is empty to begin with
	docs, err := es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(0), docs)

	// make sure the dependencies twirp and internal API are not called
	mockTwripReposAPI.EXPECT().GetRepositories(gomock.Any(), gomock.Any()).Times(0)
	mockReposDeleter.EXPECT().DeletedRepositoriesOnDotcom(gomock.Any(), []ts.RepositoryEID{possiblyDeletedRepo.RepositoryID}).Times(1)
	mockReposInternalAPI.EXPECT().GetReposAudits(gomock.Any(), ghapi.RepoAuditsRequest{RepositoryIDs: []ts.RepositoryEID{possiblyDeletedRepo.RepositoryID}}).Times(0)
	mockReposDeleter.EXPECT().InsertRepositoryForDeletion(gomock.Any(), repo1.RepositoryID).Times(0)

	// Run repo indexer without mocking the dotcom Twirp repo API
	err = runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(2), totalUpdated)

	// Verify the new index doc count
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))
	docs, err = es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(2), docs)
}

func TestInsertRepoForDeletion_WithReposToDelete(t *testing.T) {
	db, mockReposTwirpAPI, _, mockReposDeleter := setUpEnvironment(t)
	ctx, reposToDelete := context.Background(), setUpReposToDelete(t, db)

	var repoIDs []ts.RepositoryEID
	for _, repoToDelete := range reposToDelete {
		repoIDs = append(repoIDs, repoToDelete.RepositoryID)
	}
	mockReposTwirpAPI.EXPECT().GetRepositories(gomock.Any(), repoIDs).Return(reposToDelete, nil)

	mockReposDeleter.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil)
	for _, repoID := range repoIDs {
		mockReposDeleter.EXPECT().InsertRepositoryForDeletion(gomock.Any(), repoID).Return(nil).Times(1)
	}
	args := &arguments{
		targets:   []string{TargetOldest},
		repoStep:  100,
		alertStep: 100,
	}
	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(len(repoIDs)), totalUpdated)
}

func TestInsertRepoForDeletion_WithNoReposDeletedOnDotcom(t *testing.T) {
	db, mockReposTwirpAPI, _, mockReposDeleter := setUpEnvironment(t)
	ctx, reposToDelete := context.Background(), setUpReposToDelete(t, db)

	var repoIDs []ts.RepositoryEID
	for _, repoToDelete := range reposToDelete {
		repoIDs = append(repoIDs, repoToDelete.RepositoryID)
	}

	mockReposTwirpAPI.EXPECT().GetRepositories(gomock.Any(), repoIDs).Return(reposToDelete, nil)
	mockReposDeleter.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return([]ts.RepositoryEID{}, nil)
	mockReposDeleter.EXPECT().InsertRepositoryForDeletion(gomock.Any(), gomock.Any()).Times(0)
	args := &arguments{
		targets:   []string{TargetActive, TargetOldest, TargetRepo},
		horizon:   72,
		repoStep:  100,
		alertStep: 100,
	}
	err := runRepoIndexer(ctx, args)
	require.NoError(t, err)
	require.Equal(t, uint(len(repoIDs)), totalUpdated)
}

func TestInsertRepoForDeletion_WithError(t *testing.T) {
	db, mockReposTwirpAPI, _, mockReposDeleter := setUpEnvironment(t)
	ctx, reposToDelete := context.Background(), setUpReposToDelete(t, db)

	var repoIDs []ts.RepositoryEID
	for _, repoToDelete := range reposToDelete {
		repoIDs = append(repoIDs, repoToDelete.RepositoryID)
	}
	mockReposTwirpAPI.EXPECT().GetRepositories(gomock.Any(), repoIDs).Return(reposToDelete, nil)
	mockReposDeleter.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(nil, errors.New("some error from internal api"))
	mockReposDeleter.EXPECT().InsertRepositoryForDeletion(gomock.Any(), gomock.Any()).Times(0)
	args := &arguments{
		targets:   []string{TargetActive, TargetOldest, TargetRepo},
		horizon:   72,
		repoStep:  100,
		alertStep: 100,
	}
	err := runRepoIndexer(ctx, args)
	// atm if there's an error during the repos-for-deletion handling, we only log, but do not return an error.
	require.NoError(t, err)
	require.Equal(t, uint(len(repoIDs)), totalUpdated)
}

// setUpReposToDelete arranges the needed data to test the repos-for-deletion flow
func setUpReposToDelete(t *testing.T, db *gorm.DB) []*ts.Repository {
	t.Helper()
	defaultRef := []byte("refs/heads/main")
	twoYearsAgo := sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	oneYearAgo := sqltime.Date(2021, time.February, 16, 0, 0, 0, 0, time.UTC)

	reposToDelete := []*ts.Repository{
		{RepositoryID: 1, SourceUpdatedAt: twoYearsAgo, LastIndexedAt: validTime(twoYearsAgo), DefaultRef: defaultRef},
		{RepositoryID: 2, SourceUpdatedAt: oneYearAgo, LastIndexedAt: validTime(oneYearAgo), DefaultRef: defaultRef},
		{RepositoryID: 3, OwnerID: 1, SourceUpdatedAt: oneYearAgo, LastIndexedAt: validTime(oneYearAgo), DefaultRef: []byte{}},
	}

	for _, repo := range reposToDelete {
		dbtest.RequireCreate(t, db, repo)
	}

	return reposToDelete
}
