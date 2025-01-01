package elasticsearch

import (
	"context"
	"database/sql"
	"sort"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/olivere/elastic"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
)

func TestCreateIndex(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	// Delete the existing index so we don't accidentally rely on the setup
	_, err := es.es.DeleteIndex(orgLevelIndex.name).Do(ctx)
	require.NoError(t, err)

	err = es.CreateIndex(ctx, ts.Index_OrgLevel, true)
	require.NoError(t, err)

	// Check that the index was re-created
	_, err = es.es.IndexExists(orgLevelIndex.readAlias).Do(ctx)
	require.NoError(t, err)

	// Check that both aliases were created
	aliases, err := es.es.Aliases().Do(ctx)
	require.NoError(t, err)
	writeAliases := aliases.IndicesByAlias(orgLevelIndex.writeAlias)
	require.Len(t, writeAliases, 1)
	require.Equal(t, orgLevelIndex.name, writeAliases[0])
	readAliases := aliases.IndicesByAlias(orgLevelIndex.readAlias)
	require.Len(t, readAliases, 1)
	require.Equal(t, orgLevelIndex.name, readAliases[0])
}

func TestIndexAndSearch(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	err := es.IndexDocuments(ctx,
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
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			}},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Query that does not match
	res, err := es.SearchRule(ctx, ts.RepositoryEID(1), ts.SearchFilter{QueryString: "potato"})
	require.NoError(t, err)
	require.Len(t, res, 0)

	// Blank query matches all rules
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), ts.SearchFilter{QueryString: ""})
	require.NoError(t, err)
	require.Len(t, res, 2)
	require.Contains(t, res, "js/xss")
	require.Contains(t, res, "java/xss")

	// Query does match
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), ts.SearchFilter{QueryString: "XSS"})
	require.NoError(t, err)
	require.Len(t, res, 2)
	require.Contains(t, res, "js/xss")
	require.Contains(t, res, "java/xss")

	// invalid query syntax
	_, err = es.SearchRule(ctx, ts.RepositoryEID(1), ts.SearchFilter{QueryString: "foo:"})
	require.Equal(t, err, ts.ErrInvalidQuerySyntax)
}

func TestRepositoryFilter(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	searchFilter := ts.SearchFilter{
		QueryString: "*",
	}

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			},
			{
				RepositoryID:    "2",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	res, err := es.SearchRule(ctx, ts.RepositoryEID(999), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)

	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, "js/xss", res[0])
}

func TestSarifIdentifierFilter(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	searchFilter := ts.SearchFilter{
		QueryString: "*",
	}

	err := es.IndexDocuments(ctx,
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
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	searchFilter.RuleSarifIDs = []string{"foo"}
	res, err := es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)

	searchFilter.RuleSarifIDs = []string{"js/xss"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, searchFilter.RuleSarifIDs[0], res[0])

	searchFilter.QueryString = "foo"
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)
}

func TestTagsFilter(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	searchFilter := ts.SearchFilter{}

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
				Tags:            []string{"foo", "bar"},
			},
			{
				RepositoryID:    "1",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
				Tags:            []string{"baz"},
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	searchFilter.RuleTags = []string{"xss"}
	res, err := es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)

	searchFilter.RuleTags = []string{"baz"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, "java/xss", res[0])

	searchFilter.RuleTags = []string{"foo", "bar"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)

	searchFilter.RuleTags = []string{"foo", "baz"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)

	searchFilter.QueryString = "foo"
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)
}

func TestExcludedTagsFilter(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	searchFilter := ts.SearchFilter{}

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
				Tags:            []string{"foo", "bar"},
			},
			{
				RepositoryID:    "1",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
				Tags:            []string{"baz"},
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	searchFilter.ExcludedRuleTags = []string{"xss"}
	res, err := es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 2)

	searchFilter.ExcludedRuleTags = []string{"bar"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, "java/xss", res[0])

	searchFilter.ExcludedRuleTags = []string{"foo", "bar"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)

	searchFilter.ExcludedRuleTags = []string{"foo", "baz"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)
}

func TestTagsWithQueryStringFilter(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	searchFilter := ts.SearchFilter{QueryString: "bad"}

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is not good",
				SarifIdentifier: "js/xss",
				Tags:            []string{"foo", "bar"},
			},
			{
				RepositoryID:    "1",
				AlertID:         43,
				FullDescription: "XSS is bad",
				SarifIdentifier: "java/xss",
				Tags:            []string{"baz"},
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	searchFilter.RuleTags = []string{"baz"}
	res, err := es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 1)
	require.Equal(t, "java/xss", res[0])

	// does not match because of the additional query string
	searchFilter.RuleTags = []string{"foo", "bar"}
	res, err = es.SearchRule(ctx, ts.RepositoryEID(1), searchFilter)
	require.NoError(t, err)
	require.Len(t, res, 0)
}

func TestCountDocuments(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	count, err := es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(0), count)

	err = es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				Tags:            []string{"foo", "bar"},
			},
			{
				RepositoryID:    "1",
				AlertID:         43,
				FullDescription: "XSS is bad",
				Tags:            []string{"baz"},
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	count, err = es.CountAllDocuments(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.Equal(t, int64(2), count)
}

func TestStartMigration(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	now := time.Now().Add(-1 * time.Second)

	orgLevelIndex = &IndexConfig{
		name:        "org-migration-test-2",
		readAlias:   "org-migration-test-read",
		writeAlias:  "org-migration-test-write",
		mirrorAlias: "org-migration-test-mirror",
		mapping:     orglevelMapping,
	}

	err := es.CreateIndex(ctx, ts.Index_OrgLevel, true)
	require.NoError(t, err)

	time1, err := es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.True(t, time1.After(now))

	// Wait a bit and check if the same migration timestamp is returned
	time.Sleep(1 * time.Second)

	time2, err := es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	require.Equal(t, *time1, *time2)
}

func TestMirrorAliasMigration(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	orgLevelIndex = &IndexConfig{
		name:        "org-migration-test-1",
		readAlias:   "org-migration-test-read",
		writeAlias:  "org-migration-test-write",
		mirrorAlias: "org-migration-test-mirror",
		mapping:     orglevelMapping,
	}

	// Set up index and aliases
	err := es.CreateIndex(ctx, ts.Index_OrgLevel, true)
	require.NoError(t, err)
	_, err = es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	err = es.CompleteMigration(ctx, ts.Index_OrgLevel, true)
	require.NoError(t, err)

	// Confirm that migration is not required
	migrationRequired, err := es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.False(t, migrationRequired)

	// New index, meaning we need to migrate but we skip deleting the migrated index
	orgLevelIndex.name = "org-migration-test-2"

	err = es.CreateIndex(ctx, ts.Index_OrgLevel, true)
	require.NoError(t, err)

	migrationRequired, err = es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.True(t, migrationRequired)
	_, err = es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	err = es.CompleteMigration(ctx, ts.Index_OrgLevel, false)
	require.NoError(t, err)

	// Migration is still required because we did not delete migrated index
	migrationRequired, err = es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.True(t, migrationRequired)
	_, err = es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	err = es.CompleteMigration(ctx, ts.Index_OrgLevel, true) // Delete the index now which also results in the mirror alias being deleted
	require.NoError(t, err)
	migrationRequired, err = es.MigrationRequired(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)
	require.False(t, migrationRequired)
}

func TestIndexingErrors(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	orgLevelIndex.writeAlias = "foo"
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:    "1",
				AlertID:         42,
				FullDescription: "XSS is bad",
				SarifIdentifier: "js/xss",
			}},
	)
	require.Error(t, err, ts.ErrIndexNotFound)
}

func TestGetDocument(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	result, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Nil(t, result)

	boolTrue := true
	now := sqltime.Now()
	doc := &ts.SearchDocument{
		RepositoryID:        "1",
		AlertID:             1,
		SarifIdentifier:     "js/xss",
		RuleName:            "XSS",
		ShortDescription:    "XSS is bad",
		FullDescription:     "XSS is bad. No, really.",
		Help:                "Helpful information about XSS",
		Tags:                []string{"foo", "bar"},
		OwnerID:             "2",
		CanonicalID:         "3",
		Tool:                "tool",
		Severity:            "high",
		Weight:              1,
		FixedOnDefault:      &boolTrue,
		Resolved:            &boolTrue,
		CodeScanningEnabled: &boolTrue,
		CreatedAt:           &now,
		UpdatedAt:           &now,
	}
	err = es.IndexDocuments(ctx, ts.Index_OrgLevel, []*ts.SearchDocument{doc})
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	result, err = es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, doc, result)

}

func TestUpdateAlert(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	codeScanningEnabled := true
	resolved := false
	fixedOnDefault := false
	deleted := false

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				AlertID:             1,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				Resolved:            &resolved,
				FixedOnDefault:      &fixedOnDefault,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				AlertID:             2,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				FixedOnDefault:      &fixedOnDefault,
				Deleted:             &deleted,
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	now := sqltime.Now()

	// Updating resolved for alert 1
	updates := map[string]interface{}{
		"resolved":   true,
		"updated_at": now,
	}
	err = es.UpdateAlerts(ctx, 1, []ts.LogicalAlertID{1}, updates)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// The alert belonging to repository 1 should be updated
	alertDoc1, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.True(t, *alertDoc1.Resolved)
	require.Equal(t, &now, alertDoc1.UpdatedAt)

	// The other alert should be untouched

	alertDoc2, err := es.GetDocument(ctx, ts.Index_OrgLevel, 2)
	require.NoError(t, err)
	require.Nil(t, alertDoc2.Resolved)
	require.Nil(t, alertDoc2.UpdatedAt)

	// Bulk update both alerts to false
	updates["resolved"] = false
	err = es.UpdateAlerts(ctx, 1, []ts.LogicalAlertID{1, 2}, updates)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// The alert belonging to repository 1 should be updated
	alertDoc1, err = es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.False(t, *alertDoc1.Resolved)
	require.Equal(t, &now, alertDoc1.UpdatedAt)

	// The other alert should now be updated too
	alertDoc2, err = es.GetDocument(ctx, ts.Index_OrgLevel, 2)
	require.NoError(t, err)
	require.False(t, *alertDoc2.Resolved)
	require.Equal(t, &now, alertDoc2.UpdatedAt)

	resolved_at := sqltime.Now()
	// Update a different field for alert 1
	updates = map[string]interface{}{
		"resolved_at": resolved_at,
		"updated_at":  now,
	}
	err = es.UpdateAlerts(ctx, 1, []ts.LogicalAlertID{1}, updates)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// The alert belonging to repository 1 should be updated
	alertDoc1, err = es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, &resolved_at, alertDoc1.ResolvedAt)
}

func TestAddCampaignEIDToAlerts(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	codeScanningEnabled := true
	resolved := false
	fixedOnDefault := false
	deleted := false

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				AlertID:             1,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				Resolved:            &resolved,
				FixedOnDefault:      &fixedOnDefault,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				AlertID:             2,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				FixedOnDefault:      &fixedOnDefault,
				Deleted:             &deleted,
				SecurityCampaignIDs: []string{"2"},
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	err = es.AddCampaignEIDToAlerts(ctx, []ts.LogicalAlertID{1, 2}, ts.SecurityCampaignEID(1))
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Both documents should be updated
	alertDoc1, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, []string{"1"}, alertDoc1.SecurityCampaignIDs)
	alertDoc2, err := es.GetDocument(ctx, ts.Index_OrgLevel, 2)
	require.NoError(t, err)
	require.Equal(t, []string{"2", "1"}, alertDoc2.SecurityCampaignIDs)

}

func TestUpdateByQuery(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)
	codeScanningEnabled := true

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				AlertID:             1,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				Visibility:          "public",
			},
			{
				RepositoryID:        "2",
				AlertID:             2,
				OwnerID:             "42",
				CodeScanningEnabled: &codeScanningEnabled,
				Visibility:          "public",
			}},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Updating owner id and feature status for repository 1
	repoUpdate := &ts.Repository{
		RepositoryID:        1,
		OwnerID:             43,
		CodeScanningEnabled: false,
		Visibility:          sql.NullString{String: "private", Valid: true},
	}
	err = es.UpdateRepositoryMetadata(ctx, *repoUpdate)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// The alert belonging to repository 1 should be updated
	alertDoc1, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, "43", alertDoc1.OwnerID)
	require.False(t, *alertDoc1.CodeScanningEnabled)
	require.Equal(t, "private", alertDoc1.Visibility)

	// The other alert should be untouched
	alertDoc2, err := es.GetDocument(ctx, ts.Index_OrgLevel, 2)
	require.NoError(t, err)
	require.Equal(t, "42", alertDoc2.OwnerID)
	require.True(t, *alertDoc2.CodeScanningEnabled)
	require.Equal(t, "public", alertDoc2.Visibility)
}

func TestOffsetLimit(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	// Make sure that we do not crash on any offsets
	paginations := []ts.Pagination{
		{Offset: 1, Limit: 1},
		{Offset: 9975, Limit: 25},
		{Offset: 10000, Limit: 25},
		{Offset: 1000000, Limit: 25},
	}

	for _, p := range paginations {
		results, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{}, p, ts.DefaultSearchResultsSort)
		require.NoError(t, err, "Failed for offset=%d limit=%d", p.Offset, p.Limit)
		require.Empty(t, results.AlertKeys)
	}
}

func TestSearchOrgRules(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	time1 := sqltime.Date(1001, 1, 1, 1, 1, 1, 1, time.UTC)
	time2 := sqltime.Date(1002, 1, 1, 1, 1, 1, 1, time.UTC)
	// Four alerts, two for each sarif identifier
	// with different updated_at timestamps.
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				AlertID:             1,
				OwnerID:             "42",
				SarifIdentifier:     "abc",
				ShortDescription:    "abc - desc1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				UpdatedAt:           &time1,
				Deleted:             &deleted,
				Tags:                []string{"a", "b"},
			},
			{
				RepositoryID:        "1",
				AlertID:             2,
				OwnerID:             "42",
				SarifIdentifier:     "abc",
				ShortDescription:    "abc - desc2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				UpdatedAt:           &time2, // This is the most recent alert for "abc"
				Deleted:             &deleted,
				Tags:                []string{"c", "d"},
			},
			{
				RepositoryID:        "1",
				AlertID:             3,
				OwnerID:             "777",
				SarifIdentifier:     "def",
				ShortDescription:    "def - desc1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				UpdatedAt:           &time2, // This is the most recent alert for "def"
				Deleted:             &deleted,
				Tags:                []string{"e", "f"},
			},
			{
				RepositoryID:        "1",
				AlertID:             4,
				OwnerID:             "777",
				SarifIdentifier:     "def",
				ShortDescription:    "def - desc2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				UpdatedAt:           &time1,
				Deleted:             &deleted,
				Tags:                []string{"g", "h"},
			},
		},
	)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	rules, err := es.SearchOrgRules(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}})
	require.NoError(t, err)
	require.Len(t, rules, 2)
	require.Equal(t, "abc", rules[0].SarifIdentifier)
	require.Equal(t, "abc - desc2", rules[0].ShortDescription)
	require.Equal(t, uint64(2), rules[0].AlertCount)
	require.Equal(t, []string{"c", "d"}, rules[0].Tags)
	require.Equal(t, "def", rules[1].SarifIdentifier)
	require.Equal(t, "def - desc1", rules[1].ShortDescription)
	require.Equal(t, uint64(2), rules[1].AlertCount)
	require.Equal(t, []string{"e", "f"}, rules[1].Tags)

	rules, err = es.SearchOrgRules(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, "abc", rules[0].SarifIdentifier)
	require.Equal(t, "abc - desc2", rules[0].ShortDescription)
	require.Equal(t, uint64(2), rules[0].AlertCount)
	require.Equal(t, []string{"c", "d"}, rules[0].Tags)

	rules, err = es.SearchOrgRules(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}})
	require.NoError(t, err)
	require.Len(t, rules, 1)
	require.Equal(t, "def", rules[0].SarifIdentifier)
	require.Equal(t, "def - desc1", rules[0].ShortDescription)
	require.Equal(t, uint64(2), rules[0].AlertCount)
	require.Equal(t, []string{"e", "f"}, rules[0].Tags)
}

func TestOrgFreetextSearch(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "2",
				FullDescription:     "XSS is good",
				SarifIdentifier:     "js/good-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "777",
				AlertID:             2,
				CanonicalID:         "2",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     "java/bad-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			}},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query that does not match
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, QueryString: "potato"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, QueryString: "potato"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, QueryString: "potato"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	// Blank query matches all rules
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, QueryString: ""}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, QueryString: ""}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, QueryString: ""}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 2)

	// Query matches both rules
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, QueryString: "XSS"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, QueryString: "XSS"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, QueryString: "XSS"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 2)

	// Query matches single rule
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, QueryString: "bad"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, QueryString: "bad"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, QueryString: "bad"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	// Invalid query returns empty results
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, QueryString: "foo:[bar]"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)
}

func TestOrgSearchWithCursors(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				SarifIdentifier:     "js/good-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     "java/bad-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
				UpdatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
			},
			{
				RepositoryID:        "1",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				FullDescription:     "XSS is mediocre",
				SarifIdentifier:     "java/mediocre-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				CreatedAt:           &sqltime.Time{Time: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Test paging through the results using a cursor
	filter := &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Initial page (page 1)
	p := ts.Pagination{Limit: 1}
	page1, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page1.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), page1.AlertKeys[0].LogicalAlertID)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page is page 2
	p = ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page1.NextCursor, Descending: false}}
	page2, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page2.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(2), page2.AlertKeys[0].LogicalAlertID)

	// Prev page is page 1
	p = ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Equal(t, page1, result)

	// Next page is page 3
	p = ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page2.NextCursor}}
	page3, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page3.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), page3.AlertKeys[0].LogicalAlertID)
	require.Empty(t, page3.NextCursor) //  No more pages

	// Prev page is page 2
	p = ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page3.PrevCursor, Descending: true}}
	result, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Equal(t, page2, result)

	// Test pagination links for multiple results

	// Initial page should include alerts 1 and 2
	p = ts.Pagination{Limit: 2}
	page1, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page1.AlertKeys, 2)
	require.Equal(t, ts.LogicalAlertID(1), page1.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.LogicalAlertID(2), page1.AlertKeys[1].LogicalAlertID)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page should include alert 3
	p = ts.Pagination{Limit: 2, Cursor: &ts.SerializedCursor{String: page1.NextCursor}}
	page2, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page2.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), page2.AlertKeys[0].LogicalAlertID)
	require.Empty(t, page2.NextCursor) //  No more pages

	// Previous page should be identical to page 1
	p = ts.Pagination{Limit: 2, Cursor: &ts.SerializedCursor{String: page2.PrevCursor, Descending: true}}
	result, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	// The following equality check applies to alert information and the prev/next cursors
	require.Equal(t, page1, result)

	// Test limited results when only one org is provided

	filter = &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}}

	// Initial page (page 1)
	p = ts.Pagination{Limit: 1}
	page1, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page1.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), page1.AlertKeys[0].LogicalAlertID)
	require.Empty(t, page1.PrevCursor) //  No previous page
	require.Empty(t, page1.NextCursor) //  No next page

	// Test paging through the results using a cursor, sorting by updated_at (ASC)
	filter = &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}}
	s = ts.SearchSortFromProto(proto.AlertSortOrder_UPDATED_ASCENDING)

	// Initial page (page 1)
	p = ts.Pagination{Limit: 1}
	page1, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page1.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), page1.AlertKeys[0].LogicalAlertID)
	require.Empty(t, page1.PrevCursor) //  No previous page

	// Next page is page 2
	p = ts.Pagination{Limit: 1, Cursor: &ts.SerializedCursor{String: page1.NextCursor, Descending: false}}
	page2, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, page2.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(2), page2.AlertKeys[0].LogicalAlertID)
}

func TestOrgSearchWithResolution(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := true
	resolved := true
	enabled := true
	deleted := false

	falsePositive := ts.AlertResolutionFalsePositive
	wontFix := ts.AlertResolutionWontFix
	usedInTests := ts.AlertResolutionUsedInTests
	fixedResolution := ts.AlertResolutionNone

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Resolution:          falsePositive.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Resolution:          wontFix.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Resolution:          usedInTests.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				Resolution:          fixedResolution.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)

	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	filter := &ts.SearchByOrgsFilter{
		OwnerIDs:   []ts.OwnerEID{42, 777},
		State:      proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
		Resolution: &falsePositive,
	}

	res, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &wontFix
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(2), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(2), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &usedInTests
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &fixedResolution
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)

	// Test limited results when only one org is provided

	filter.OwnerIDs = []ts.OwnerEID{42}
	filter.Resolution = &falsePositive

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &wontFix
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(2), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(2), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &usedInTests
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	filter.Resolution = &fixedResolution
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	filter.OwnerIDs = []ts.OwnerEID{777}
	filter.Resolution = &falsePositive

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	filter.Resolution = &wontFix
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	filter.Resolution = &usedInTests
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolution = &fixedResolution
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)
}

func TestOrgSearchWithResolutions(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := true
	resolved := true
	enabled := true
	deleted := false

	falsePositive := ts.AlertResolutionFalsePositive
	wontFix := ts.AlertResolutionWontFix
	usedInTests := ts.AlertResolutionUsedInTests
	fixedResolution := ts.AlertResolutionNone

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Resolution:          falsePositive.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Resolution:          wontFix.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Resolution:          usedInTests.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				Resolution:          fixedResolution.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)

	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	// Verify Individual alert types
	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	filter := &ts.SearchByOrgsFilter{
		OwnerIDs:    []ts.OwnerEID{42, 777},
		State:       proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
		Resolutions: []*ts.AlertResolution{&falsePositive},
	}

	res, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolutions[0] = &wontFix
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(2), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(2), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolutions[0] = &usedInTests
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolutions[0] = &fixedResolution
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)

	// Verify multiple alert queries

	filter.Resolutions[0] = &wontFix
	filter.Resolutions = append(filter.Resolutions, &usedInTests)

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 2)
	require.Equal(t, ts.LogicalAlertID(2), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(2), res.AlertKeys[0].PhysicalAlertID)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[1].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[1].PhysicalAlertID)

	// Test limited results when only one org is provided

	filter.OwnerIDs = []ts.OwnerEID{42}
	filter.Resolutions = []*ts.AlertResolution{&falsePositive}

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	filter.Resolutions = append(filter.Resolutions, &wontFix)
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 2)
	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)
	require.Equal(t, ts.LogicalAlertID(2), res.AlertKeys[1].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(2), res.AlertKeys[1].PhysicalAlertID)
}

func TestSearchOrgRepositoryIDs(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// must refresh to enable aggregations
	err = es.Refresh(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	results, err := es.SearchOrgRepositoryIDs(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].RepositoryId < results[j].RepositoryId
	})

	require.Len(t, results, 3)
	require.Equal(t, uint64(1), results[0].RepositoryId)
	require.Equal(t, uint64(2), results[0].AlertCount)
	require.Equal(t, uint64(2), results[1].RepositoryId)
	require.Equal(t, uint64(1), results[1].AlertCount)
	require.Equal(t, uint64(3), results[2].RepositoryId)
	require.Equal(t, uint64(1), results[2].AlertCount)

	// Test limited results when only one org is provided

	results, err = es.SearchOrgRepositoryIDs(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].RepositoryId < results[j].RepositoryId
	})

	require.Len(t, results, 1)
	require.Equal(t, uint64(1), results[0].RepositoryId)
	require.Equal(t, uint64(2), results[0].AlertCount)

	results, err = es.SearchOrgRepositoryIDs(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].RepositoryId < results[j].RepositoryId
	})

	require.Len(t, results, 2)
	require.Equal(t, uint64(2), results[0].RepositoryId)
	require.Equal(t, uint64(1), results[0].AlertCount)
	require.Equal(t, uint64(3), results[1].RepositoryId)
	require.Equal(t, uint64(1), results[1].AlertCount)

	results, err = es.SearchOrgRepositoryIDs(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, RepositoryIDs: []ts.RepositoryEID{3}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].RepositoryId < results[j].RepositoryId
	})

	require.Len(t, results, 1)
	require.Equal(t, uint64(3), results[0].RepositoryId)
	require.Equal(t, uint64(1), results[0].AlertCount)
}

func TestSearchOrgToolNames(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				OwnerID:             "42",
				AlertID:             1,
				Tool:                "CodeQL",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "42",
				AlertID:             2,
				Tool:                "CodeQL",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "42",
				AlertID:             3,
				Tool:                "Fortify",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// must refresh to enable aggregations
	err = es.Refresh(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	results, err := es.SearchOrgToolNames(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].Name < results[j].Name
	})

	require.Len(t, results, 2)
	require.Equal(t, "CodeQL", results[0].Name)
	require.Equal(t, uint64(2), results[0].AlertCount)
	require.Equal(t, "Fortify", results[1].Name)
	require.Equal(t, uint64(1), results[1].AlertCount)
}

func TestSearchOrgRuleTags(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				OwnerID:             "42",
				AlertID:             1,
				Tags:                []string{"maintainability", "readability", "experimental"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "42",
				AlertID:             2,
				Tags:                []string{"maintainability", "experimental"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "42",
				AlertID:             3,
				Tags:                []string{"external/cwe/cwe-020"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// must refresh to enable aggregations
	err = es.Refresh(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	results, err := es.SearchOrgRuleTags(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].Tag < results[j].Tag
	})

	require.Len(t, results, 4)
	require.Equal(t, "experimental", results[0].Tag)
	require.Equal(t, uint64(2), results[0].AlertCount)
	require.Equal(t, "external/cwe/cwe-020", results[1].Tag)
	require.Equal(t, uint64(1), results[1].AlertCount)
	require.Equal(t, "maintainability", results[2].Tag)
	require.Equal(t, uint64(2), results[2].AlertCount)
	require.Equal(t, "readability", results[3].Tag)
	require.Equal(t, uint64(1), results[3].AlertCount)
}

func TestSearchOrgSeverities(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				OwnerID:             "42",
				AlertID:             1,
				Severity:            "HIGH",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "42",
				AlertID:             2,
				Severity:            "HIGH",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "777",
				AlertID:             3,
				Severity:            "ERROR",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				OwnerID:             "777",
				AlertID:             4,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// must refresh to enable aggregations
	err = es.Refresh(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	results, err := es.SearchOrgSeverities(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].Severity > results[j].Severity
	})

	require.Len(t, results, 2)
	require.Equal(t, proto.Severity_SEVERITY_HIGH, results[0].Severity)
	require.Equal(t, uint64(2), results[0].AlertCount)
	require.Equal(t, proto.Severity_SEVERITY_ERROR, results[1].Severity)
	require.Equal(t, uint64(1), results[1].AlertCount)
	// the item without Severity value will not be included

	// Test limited results when only one org is provided

	results, err = es.SearchOrgSeverities(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].Severity > results[j].Severity
	})

	require.Len(t, results, 1)
	require.Equal(t, proto.Severity_SEVERITY_HIGH, results[0].Severity)
	require.Equal(t, uint64(2), results[0].AlertCount)
	// the item without Severity value will not be included

	results, err = es.SearchOrgSeverities(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}})
	require.NoError(t, err)

	// force consistent order for tests
	sort.Slice(results, func(i, j int) bool {
		return results[i].Severity > results[j].Severity
	})

	require.Len(t, results, 1)
	require.Equal(t, proto.Severity_SEVERITY_ERROR, results[0].Severity)
	require.Equal(t, uint64(1), results[0].AlertCount)
	// the item without Severity value will not be included
}

func TestOrgSearchWithToolAndToolGuid(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Tool:                "CodeQL",
				ToolGUID:            "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Tool:                "Fortify",
				ToolGUID:            "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Tool:                "ESLint",
				ToolGUID:            "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				Tool:                "CodeQL",
				ToolGUID:            "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only tool name
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tool: "CodeQL"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, "CodeQL", res.Documents[0].Tool)
	require.Equal(t, "CodeQL", res.Documents[1].Tool)

	// Query with only tool guid
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ToolGUID: "2"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "Fortify", res.Documents[0].Tool)
	require.Equal(t, "2", res.Documents[0].ToolGUID)

	// Test limited results when only one org is provided

	// Query with only tool name
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tool: "CodeQL"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "CodeQL", res.Documents[0].Tool)

	// Query with only tool guid
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ToolGUID: "2"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "Fortify", res.Documents[0].Tool)
	require.Equal(t, "2", res.Documents[0].ToolGUID)

	// Query with only tool name
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Tool: "CodeQL"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "CodeQL", res.Documents[0].Tool)

	// Query with only tool guid
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ToolGUID: "2"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)
}

func TestOrgSearchWithMultiToolAndToolGuid(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Tool:                "CodeQL",
				ToolGUID:            "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Tool:                "Fortify",
				ToolGUID:            "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "42",
				AlertID:             3,
				CanonicalID:         "3",
				Tool:                "ESLint",
				ToolGUID:            "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "42",
				AlertID:             4,
				CanonicalID:         "4",
				Tool:                "CodeQL",
				ToolGUID:            "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only one tool name
	res1, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tools: []string{"CodeQL"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res1.Documents, 2)
	require.Equal(t, "CodeQL", res1.Documents[0].Tool)
	require.Equal(t, "CodeQL", res1.Documents[1].Tool)

	// Query with multiple tool name
	res2, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tools: []string{"CodeQL", "Fortify"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res2.Documents, 3)
	require.Equal(t, "CodeQL", res2.Documents[0].Tool)
	require.Equal(t, "Fortify", res2.Documents[1].Tool)
	require.Equal(t, "CodeQL", res2.Documents[2].Tool)

	// Query with only one tool guid
	res3, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ToolGUIDs: []string{"2"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res3.Documents, 1)
	require.Equal(t, "Fortify", res3.Documents[0].Tool)
	require.Equal(t, "2", res3.Documents[0].ToolGUID)

	// Query with only one tool guid
	res4, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ToolGUIDs: []string{"2", "3"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res4.Documents, 2)
	require.Equal(t, "Fortify", res4.Documents[0].Tool)
	require.Equal(t, "2", res4.Documents[0].ToolGUID)
	require.Equal(t, "ESLint", res4.Documents[1].Tool)
	require.Equal(t, "3", res4.Documents[1].ToolGUID)

	res5, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tools: []string{"CodeQL", "Fortify"}, ToolGUIDs: []string{"3"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res5.Documents, 3)
	require.Equal(t, "CodeQL", res5.Documents[0].Tool)
	require.Equal(t, "Fortify", res5.Documents[1].Tool)
	require.Equal(t, "CodeQL", res5.Documents[2].Tool)
}

func TestOrgSearchWithRepositoryIDs(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.AlertIDSort

	for i := 1; i <= 2; i++ {
		repositoryIDs := []ts.RepositoryEID{ts.RepositoryEID(i)}

		// Query with repository IDs
		res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, RepositoryIDs: repositoryIDs}, p, s)
		require.NoError(t, err)
		require.Len(t, res.AlertKeys, 1)
		require.Equal(t, ts.LogicalAlertID(i), res.AlertKeys[0].LogicalAlertID)

		// Query with repository IDs but omitting owner IDs still returns expected results
		res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{RepositoryIDs: repositoryIDs}, p, s)
		require.NoError(t, err)
		require.Len(t, res.AlertKeys, 1)
		require.Equal(t, ts.LogicalAlertID(i), res.AlertKeys[0].LogicalAlertID)
	}
}

func TestOrgSearchWithExcludedRepositoryIDs(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only excluded repository IDs
	excludedRepositoryIDs := []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	// Query with both target repository IDs and excluded repository IDs
	repositoryIDs := []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	excludedRepositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, RepositoryIDs: repositoryIDs, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)

	// Test limited results when only one org is provided

	// Query with only excluded repository IDs
	excludedRepositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	// Query with both target repository IDs and excluded repository IDs
	repositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	excludedRepositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, RepositoryIDs: repositoryIDs, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 0)

	// Query with only excluded repository IDs
	excludedRepositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	// Query with both target repository IDs and excluded repository IDs
	repositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(3)}
	excludedRepositoryIDs = []ts.RepositoryEID{ts.RepositoryEID(1), ts.RepositoryEID(2)}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, RepositoryIDs: repositoryIDs, ExcludedRepositoryIDs: excludedRepositoryIDs}, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)
}

func TestOrgSearchWithExcludedTools(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Tool:                "CodeQL",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Tool:                "Fortify",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Tool:                "ESLint",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				Tool:                "CodeQL",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only excluded tools
	excludedTools := []string{"CodeQL", "ESLint"}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "Fortify", res.Documents[0].Tool)

	// Query with both target Tools and excluded tools
	tool := "ESLint"
	excludedTools = []string{"CodeQL", "Fortify"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, tool, res.Documents[0].Tool)

	// Query when target Tools and excluded tools are the same
	tool = "CodeQL"
	excludedTools = []string{"CodeQL"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Test limited results when only one org is provided

	// Query with only excluded tools
	excludedTools = []string{"CodeQL", "ESLint"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "Fortify", res.Documents[0].Tool)

	// Query with both target Tools and excluded tools
	tool = "ESLint"
	excludedTools = []string{"CodeQL", "Fortify"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query when target Tools and excluded tools are the same
	tool = "CodeQL"
	excludedTools = []string{"CodeQL"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query with only excluded tools
	excludedTools = []string{"CodeQL", "ESLint"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query with both target Tools and excluded tools
	tool = "ESLint"
	excludedTools = []string{"CodeQL", "Fortify"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, tool, res.Documents[0].Tool)

	// Query when target Tools and excluded tools are the same
	tool = "CodeQL"
	excludedTools = []string{"CodeQL"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Tool: tool, ExcludedTools: excludedTools}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)
}

func TestOrgSearchWithExcludedSeverities(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Severity:            "HIGH",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Severity:            "MEDIUM",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Severity:            "LOW",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only excluded severities
	excludedSeverities := []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, "LOW", res.Documents[0].Severity)
	require.Equal(t, "", res.Documents[1].Severity) // No severity item also show up in the list

	// Query with target severity and excluded severities
	severity := proto.Severity_SEVERITY_LOW
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "LOW", res.Documents[0].Severity)
	// No severity item does not show up as target severity is LOW

	// Query when target severity and excluded severities are the same
	severity = proto.Severity_SEVERITY_LOW
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Test limited results when a single org is provided

	// Query with only excluded severities
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query with target severity and excluded severities
	severity = proto.Severity_SEVERITY_LOW
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query when target severity and excluded severities are the same
	severity = proto.Severity_SEVERITY_MEDIUM
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query with only excluded severities
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "", res.Documents[0].Severity) // No severity item also show up in the list

	// Query with target severity and excluded severities
	severity = proto.Severity_SEVERITY_LOW
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "LOW", res.Documents[0].Severity)
	// No severity item does not show up as target severity is LOW

	// Query when target severity and excluded severities are the same
	severity = proto.Severity_SEVERITY_LOW
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Severity: severity, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)
}

func TestOrgSearchWithMultiSeverities(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Severity:            "HIGH",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Severity:            "MEDIUM",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Severity:            "LOW",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "3",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	severities := []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, "HIGH", res.Documents[0].Severity)
	require.Equal(t, "MEDIUM", res.Documents[1].Severity)

	// Query with target severity and excluded severities
	severities = []proto.Severity{proto.Severity_SEVERITY_LOW}
	excludedSeverities := []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_MEDIUM}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "LOW", res.Documents[0].Severity)

	// Excluded Severities are a subset of Severities
	severities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_LOW}
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_HIGH}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "LOW", res.Documents[0].Severity)
	// Query when target severity and excluded severities are the same
	severities = []proto.Severity{proto.Severity_SEVERITY_LOW}
	excludedSeverities = []proto.Severity{proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities, ExcludedSeverities: excludedSeverities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Apply both filters when Severities and Severity are both provided.
	severity := proto.Severity_SEVERITY_HIGH
	severities = []proto.Severity{proto.Severity_SEVERITY_MEDIUM, proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities, Severity: severity}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	severity = proto.Severity_SEVERITY_HIGH
	severities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Severities: severities, Severity: severity}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "HIGH", res.Documents[0].Severity)

	// Test limited results when a single org is provided

	severities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Severities: severities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "HIGH", res.Documents[0].Severity)

	severities = []proto.Severity{proto.Severity_SEVERITY_HIGH, proto.Severity_SEVERITY_LOW}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Severities: severities}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "LOW", res.Documents[0].Severity)
}

func TestOrgSearchWithExcludedResolutions(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := true
	resolved := true
	enabled := true
	deleted := false

	falsePositive := ts.AlertResolutionFalsePositive
	wontFix := ts.AlertResolutionWontFix
	usedInTests := ts.AlertResolutionUsedInTests
	fixedResolution := ts.AlertResolutionNone

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Resolution:          falsePositive.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Resolution:          wontFix.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Resolution:          usedInTests.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             4,
				CanonicalID:         "4",
				Resolution:          fixedResolution.String(),
				Resolved:            &resolved,
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)

	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)
	filter := &ts.SearchByOrgsFilter{
		OwnerIDs: []ts.OwnerEID{42, 777},
		State:    proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
	}

	filter.ExcludedResolutions = []*ts.AlertResolution{&wontFix}
	res, err := es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 3)

	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[1].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[1].PhysicalAlertID)

	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[2].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[2].PhysicalAlertID)

	// Search with Resolution and ExcludedResolutions
	filter.Resolution = &usedInTests
	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)
	require.Equal(t, ts.LogicalAlertID(3), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(3), res.AlertKeys[0].PhysicalAlertID)

	// Test limited results when a single org is provided
	filter = &ts.SearchByOrgsFilter{
		OwnerIDs:            []ts.OwnerEID{42},
		State:               proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
		ExcludedResolutions: []*ts.AlertResolution{&wontFix},
	}

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	require.Equal(t, ts.LogicalAlertID(1), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(1), res.AlertKeys[0].PhysicalAlertID)

	filter = &ts.SearchByOrgsFilter{
		OwnerIDs:            []ts.OwnerEID{777},
		State:               proto.AlertStateFilter_ALERT_STATE_FILTER_CLOSED,
		ExcludedResolutions: []*ts.AlertResolution{&usedInTests},
	}

	res, err = es.SearchOrgAlerts(ctx, filter, p, s)
	require.NoError(t, err)
	require.Len(t, res.AlertKeys, 1)

	require.Equal(t, ts.LogicalAlertID(4), res.AlertKeys[0].LogicalAlertID)
	require.Equal(t, ts.PhysicalAlertID(4), res.AlertKeys[0].PhysicalAlertID)
}

func TestOrgSearchWithExcludedSarifIdentifiers(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				SarifIdentifier:     "js/good-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     "js/bad-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				FullDescription:     "XSS is mediocre",
				SarifIdentifier:     "java/mediocre-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with only excluded sarifIdentifiers
	excludedSarifIdentifiers := []string{"js/good-xss", "js/bad-xss"}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedSarifIdentifiers: excludedSarifIdentifiers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "java/mediocre-xss", res.Documents[0].SarifIdentifier)

	// Query with target sarifIdentifier and excluded sarifIdentifiers
	sarifIdentifier := "java/mediocre-xss"
	excludedSarifIdentifiers = []string{"js/good-xss", "js/bad-xss"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, SarifIdentifier: sarifIdentifier, ExcludedSarifIdentifiers: excludedSarifIdentifiers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, sarifIdentifier, res.Documents[0].SarifIdentifier)

	// Query when target sarifIdentifier and excluded sarifIdentifiers are the same
	sarifIdentifier = "java/mediocre-xss"
	excludedSarifIdentifiers = []string{sarifIdentifier}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, SarifIdentifier: sarifIdentifier, ExcludedSarifIdentifiers: excludedSarifIdentifiers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Test limited results when a single org is provided

	excludedSarifIdentifiers = []string{"js/good-xss"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ExcludedSarifIdentifiers: excludedSarifIdentifiers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "js/bad-xss", res.Documents[0].SarifIdentifier)

	excludedSarifIdentifiers = []string{"java/mediocre-xss"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ExcludedSarifIdentifiers: excludedSarifIdentifiers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)
}

func TestOrgSearchWithRuleTagsAndExcludedRuleTags(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FullDescription:     "XSS is good",
				Tags:                []string{"external/cwe/cwe-079", "experimental"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FullDescription:     "SQL injection is bad",
				Tags:                []string{"external/cwe/cwe-089", "external/cwe/cwe-050"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				FullDescription:     "XSS is mediocre",
				Tags:                []string{"external/cwe/cwe-020"},
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with multiple included tags
	tags := []string{"external/cwe/cwe-100", "external/cwe/cwe-020"}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tags: tags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(3), res.Documents[0].AlertID)

	// Query with target tags and excluded tags are the same
	excludedTags := []string{"external/cwe/cwe-020"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tags: tags, ExcludedTags: excludedTags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	// Query with an included tag and a case-sensitive tag
	tags = []string{"external/cwe/cwe-050", "external/cwe/CWE-020"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tags: tags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)

	// Query with a single excluded tag
	excludedTags = []string{"external/cwe/cwe-050"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedTags: excludedTags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.ElementsMatch(t, []uint64{1, 3}, transforms.Map(res.Documents, func(t ts.SearchDocument) uint64 {
		return t.AlertID
	}))

	// Query with multiple excluded tags
	excludedTags = []string{"external/cwe/cwe-050", "experimental", "external/cwe/CWE-020"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedTags: excludedTags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(3), res.Documents[0].AlertID)

	// Test limited results when a single org is provided

	tags = []string{"external/cwe/cwe-089", "external/cwe/cwe-020"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, Tags: tags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)

	tags = []string{"external/cwe/cwe-089"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, Tags: tags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)

	excludedTags = []string{"experimental"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, ExcludedTags: excludedTags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)

	excludedTags = []string{"external/cwe/cwe-020"}
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{777}, ExcludedTags: excludedTags}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 0)
}

func TestOrgSearchCaseInsensitiveFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				Tool:                "CodeQL",
				FullDescription:     "XSS is good",
				SarifIdentifier:     "js/good-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				Tool:                "Fortify",
				FullDescription:     "XSS is bad",
				SarifIdentifier:     "js/bad-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				Tags:                []string{"security"},
			},
			{
				RepositoryID:        "2",
				OwnerID:             "777",
				AlertID:             3,
				CanonicalID:         "3",
				Tool:                "Trivy",
				FullDescription:     "XSS is mediocre",
				SarifIdentifier:     "java/mediocre-xss",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				Tags:                []string{"security"},
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with tool name
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, Tool: "codeql"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "CodeQL", res.Documents[0].Tool)

	// Query with excluded tool name
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedTools: []string{"trivy", "FORTify"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "CodeQL", res.Documents[0].Tool)

	// Query with sarif identifier
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, SarifIdentifier: "Java/Mediocre-XSS"}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "java/mediocre-xss", res.Documents[0].SarifIdentifier)

	// Query with excluded sarif identifiers
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42, 777}, ExcludedSarifIdentifiers: []string{"JS/good-xss", "JS/bad-xss"}}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, "java/mediocre-xss", res.Documents[0].SarifIdentifier)

	// TODO: Once we start supporting filtering by tags in `SearchOrgAlerts` we should replace these tests.
	caseInsensitiveQuery := elastic.NewBoolQuery().Must(elastic.NewTermQuery("tags.case_insensitive", "SECURITY"))
	caseInsensitiveCountResult, err := es.es.Count().Index(orgLevelIndex.readAlias).Query(caseInsensitiveQuery).Do(ctx)
	require.NoError(t, err)
	require.Equal(t, int64(2), caseInsensitiveCountResult)
}

func TestOrgSearchRepoNumberFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				Number:              1,
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				Number:              2,
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				Number:              1,
				OwnerID:             "42",
				AlertID:             3,
				CanonicalID:         "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				Number:              2,
				OwnerID:             "42",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Query with repo numbers
	repoNumbers := []ts.RepoNumber{{RepositoryID: ts.RepositoryEID(1), Number: 1}, {RepositoryID: ts.RepositoryEID(2), Number: 2}}
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42}, RepoNumbers: repoNumbers}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, "1", res.Documents[0].RepositoryID)
	require.Equal(t, uint32(1), res.Documents[0].Number)
	require.Equal(t, "2", res.Documents[1].RepositoryID)
	require.Equal(t, uint32(2), res.Documents[1].Number)
}

func TestOrgSearchClassificationFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				Number:              1,
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				Classification:      []string{"generated"},
			},
			{
				RepositoryID:        "1",
				Number:              2,
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "2",
				Number:              1,
				OwnerID:             "42",
				AlertID:             3,
				CanonicalID:         "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				Classification:      []string{"generated", "test"},
			},
			{
				RepositoryID:        "2",
				Number:              2,
				OwnerID:             "42",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Get alerts with no classifiers
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42},
		Classification: proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)
	require.Equal(t, uint64(4), res.Documents[1].AlertID)

	// Get alerts with at least one classifier
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42},
		Classification: proto.AlertClassificationFilter_ALERT_CLASSIFICATION_FILTER_ANY_CLASSIFICATION}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, uint64(1), res.Documents[0].AlertID)
	require.Equal(t, uint64(3), res.Documents[1].AlertID)
}

func TestOrgSearchAlertLinksFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				Number:              1,
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				Number:              2,
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				HasLinks:            true,
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Get alerts with no links
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42},
		AlertLinks: proto.AlertLinksFilter_ALERT_LINKS_FILTER_NO_LINKS}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(1), res.Documents[0].AlertID)

	// Get alerts with any link
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42},
		AlertLinks: proto.AlertLinksFilter_ALERT_LINKS_FILTER_ANY_LINKS}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)
}

func TestOrgSearchAutofixFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				Number:              1,
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				Number:              2,
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				AutofixEligible:     true,
			},
			{
				RepositoryID:        "1",
				Number:              3,
				OwnerID:             "42",
				AlertID:             3,
				CanonicalID:         "3",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				AutofixEligible:     true,
				AutofixState:        ts.SuggestedFixAlertStateValid.DBString(),
			},
			{
				RepositoryID:        "1",
				Number:              4,
				OwnerID:             "42",
				AlertID:             4,
				CanonicalID:         "4",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				AutofixEligible:     true,
				AutofixState:        ts.SuggestedFixAlertStateError.DBString(),
			},
			{
				RepositoryID:        "1",
				Number:              5,
				OwnerID:             "42",
				AlertID:             5,
				CanonicalID:         "5",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				AutofixEligible:     false, // This should not in general happen, but it is interesting to test.
				AutofixState:        ts.SuggestedFixAlertStateValid.DBString(),
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Get alerts that are eligble for autofix
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{
		OwnerIDs:  []ts.OwnerEID{42},
		Autofixes: []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED},
	}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 3)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)
	require.Equal(t, uint64(3), res.Documents[1].AlertID)
	require.Equal(t, uint64(4), res.Documents[2].AlertID)

	// Get alerts with a valid autofix
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{
		OwnerIDs:  []ts.OwnerEID{42},
		Autofixes: []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_GENERATED},
	}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, uint64(3), res.Documents[0].AlertID)
	require.Equal(t, uint64(5), res.Documents[1].AlertID)

	// Get alerts that are eligble for autofix and have a valid autofix
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{
		OwnerIDs: []ts.OwnerEID{42},
		Autofixes: []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED,
			proto.AutofixFilter_AUTOFIX_FILTER_GENERATED},
	}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(3), res.Documents[0].AlertID)

	// Get alerts that are eligble for autofix but do not have a valid autofix
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{
		OwnerIDs:          []ts.OwnerEID{42},
		Autofixes:         []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED},
		ExcludedAutofixes: []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_GENERATED},
	}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 2)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)
	require.Equal(t, uint64(4), res.Documents[1].AlertID)

	// Get alerts that are not eligble for autofix and they do not have a valid autofix
	res, err = es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{
		OwnerIDs: []ts.OwnerEID{42},
		ExcludedAutofixes: []proto.AutofixFilter{proto.AutofixFilter_AUTOFIX_FILTER_SUPPORTED,
			proto.AutofixFilter_AUTOFIX_FILTER_GENERATED},
	}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(1), res.Documents[0].AlertID)
}

func TestOrgSearchSecurityCampaignFiltering(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	fixed := false
	enabled := true
	deleted := false
	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:        "1",
				Number:              1,
				OwnerID:             "42",
				AlertID:             1,
				CanonicalID:         "1",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
			},
			{
				RepositoryID:        "1",
				Number:              2,
				OwnerID:             "42",
				AlertID:             2,
				CanonicalID:         "2",
				FixedOnDefault:      &fixed,
				CodeScanningEnabled: &enabled,
				Deleted:             &deleted,
				SecurityCampaignIDs: []string{"1", "2"},
			},
		},
	)
	require.NoError(t, err)

	// Force an index refresh to make the results visible via search
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	p := ts.Pagination{Limit: 20}
	s := ts.SearchSortFromProto(proto.AlertSortOrder_CREATED_ASCENDING)

	// Get alerts with security campaign ID 2
	res, err := es.SearchOrgAlerts(ctx, &ts.SearchByOrgsFilter{OwnerIDs: []ts.OwnerEID{42},
		SecurityCampaignIDs: []ts.SecurityCampaignEID{2}}, p, s)
	require.NoError(t, err)
	require.Len(t, res.Documents, 1)
	require.Equal(t, uint64(2), res.Documents[0].AlertID)
}

func TestUpdateCanonicalIDs(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	isFalse := false
	isTrue := true

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:   "1",
				AlertID:        1,
				CanonicalID:    "1",
				FixedOnDefault: &isTrue,
			},
			{
				RepositoryID:   "2",
				AlertID:        2,
				CanonicalID:    "2",
				FixedOnDefault: &isTrue,
			},
			// Should not get updated because it is not on default
			{
				RepositoryID: "3",
				AlertID:      3,
				CanonicalID:  "3",
			},
			// NOTE: ideally this should not be updated in some cases (depending on the created_at timestamp)
			// However we are not able to distinguish between the two cases possible cases in Elasticsearch
			// so we accept it gets updated for now.
			// See https://github.com/github/code-scanning/issues/15548.
			{
				RepositoryID:   "4",
				AlertID:        4,
				CanonicalID:    "4",
				FixedOnDefault: &isFalse,
			},
			// Should not get updated because it is not part of the updates
			{
				RepositoryID:   "5",
				AlertID:        5,
				CanonicalID:    "5",
				FixedOnDefault: &isTrue,
			},
		},
	)
	require.NoError(t, err)

	updates := map[ts.LogicalAlertID]ts.PhysicalAlertID{
		ts.LogicalAlertID(1): ts.PhysicalAlertID(11),
		ts.LogicalAlertID(2): ts.PhysicalAlertID(22),
		ts.LogicalAlertID(3): ts.PhysicalAlertID(33),
		ts.LogicalAlertID(4): ts.PhysicalAlertID(44),
	}
	err = es.UpdateCanonicalIDs(ctx, updates, 1)
	require.NoError(t, err)

	// Check that the update was successful
	doc1, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, "11", doc1.CanonicalID)
	require.Equal(t, "1", doc1.RepositoryID)
	doc2, err := es.GetDocument(ctx, ts.Index_OrgLevel, 2)
	require.NoError(t, err)
	require.Equal(t, "22", doc2.CanonicalID)
	require.Equal(t, "2", doc2.RepositoryID)

	// This document gets updated because we cannot distinguish between the
	// two cases in Elasticsearch. See note above.
	doc4, err := es.GetDocument(ctx, ts.Index_OrgLevel, 4)
	require.NoError(t, err)
	require.Equal(t, "44", doc4.CanonicalID)
	require.Equal(t, "4", doc4.RepositoryID)

	// The last two documents should not have been updated
	doc3, err := es.GetDocument(ctx, ts.Index_OrgLevel, 3)
	require.NoError(t, err)
	require.Equal(t, "3", doc3.CanonicalID)
	require.Equal(t, "3", doc3.RepositoryID)

	doc5, err := es.GetDocument(ctx, ts.Index_OrgLevel, 5)
	require.NoError(t, err)
	require.Equal(t, "5", doc5.CanonicalID)
	require.Equal(t, "5", doc5.RepositoryID)
}

func TestUpdateCanonicalIDsDuringMigrations(t *testing.T) {
	ctx := context.Background()
	es := SetUpTestElasticSearchService(t)

	isTrue := true

	err := es.IndexDocuments(ctx,
		ts.Index_OrgLevel,
		[]*ts.SearchDocument{
			{
				RepositoryID:   "1",
				AlertID:        1,
				CanonicalID:    "1",
				FixedOnDefault: &isTrue,
			},
		})
	require.NoError(t, err)
	doc, err := es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, "1", doc.CanonicalID)

	// simulate the start of an index migration
	orgLevelIndex.name = "test-index-2"
	require.NoError(t, es.CreateIndex(ctx, ts.Index_OrgLevel, true))
	_, err = es.StartMigration(ctx, ts.Index_OrgLevel)
	require.NoError(t, err)

	updates := map[ts.LogicalAlertID]ts.PhysicalAlertID{
		ts.LogicalAlertID(1): ts.PhysicalAlertID(11),
	}
	err = es.UpdateCanonicalIDs(ctx, updates, 1)
	require.NoError(t, err)

	doc, err = es.GetDocument(ctx, ts.Index_OrgLevel, 1)
	require.NoError(t, err)
	require.Equal(t, "11", doc.CanonicalID)
}
