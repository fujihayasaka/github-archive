package db

import (
	"context"
	"testing"
	"time"

	"github.com/github/configsd/internal/fixtures"
	"github.com/github/configsd/internal/model"
	stats "github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

func insertConfigEntry(t *testing.T, db *sqlx.DB, name, value string, target model.ConfigurationTarget, final bool) uint64 {
	now := time.Now()
	result, err := db.Exec(`
        INSERT INTO configuration_entries (target_id, target_type, updater_id, name, value, final, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		target.ID, targetTypeForDB(target.Type), 1, name, value, final, now, now,
	)
	require.NoError(t, err)

	id, err := result.LastInsertId()
	require.NoError(t, err)
	require.NotZero(t, id)
	return uint64(id)
}

func TestTargetTypeForDB(t *testing.T) {
	t.Run("converts Global to lowercase global", func(t *testing.T) {
		result := targetTypeForDB(model.Global)
		require.Equal(t, "global", result)
	})

	t.Run("preserves other target types as-is", func(t *testing.T) {
		testCases := []struct {
			input    model.TargetType
			expected string
		}{
			{model.Repository, "Repository"},
			{model.User, "User"},
			{model.Business, "Business"},
		}

		for _, tc := range testCases {
			result := targetTypeForDB(tc.input)
			require.Equal(t, tc.expected, result, "targetTypeForDB(%s) should return %s", tc.input, tc.expected)
		}
	})
}

func TestTargetTypeFromDB(t *testing.T) {
	t.Run("converts lowercase global to Global", func(t *testing.T) {
		result := targetTypeFromDB("global")
		require.Equal(t, model.Global, result)
	})

	t.Run("preserves other target types as-is", func(t *testing.T) {
		testCases := []struct {
			input    string
			expected model.TargetType
		}{
			{"Repository", model.Repository},
			{"User", model.User},
			{"Business", model.Business},
		}

		for _, tc := range testCases {
			result := targetTypeFromDB(tc.input)
			require.Equal(t, tc.expected, result, "targetTypeFromDB(%s) should return %s", tc.input, tc.expected)
		}
	})
}

func TestSQLStore_SetRepositoryOwner(t *testing.T) {
	db := fixtures.SetupDB(t, "configurations")

	t.Run("Set new repository owner", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			repoID := uint64(12345)
			ownerID := uint64(67890)

			// Set the repository owner
			before := time.Now().UTC()
			err = store.SetRepositoryOwner(ctx, repoID, ownerID)
			after := time.Now().UTC()
			require.NoError(t, err)

			// Verify the record was inserted
			var count int
			err = s.QueryRowContext(ctx,
				"SELECT COUNT(*) FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID).Scan(&count)
			require.NoError(t, err)
			require.Equal(t, 1, count)

			// Verify the updated_at field is within the expected time range
			var updatedAt time.Time
			err = s.QueryRowContext(ctx,
				"SELECT updated_at FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID).Scan(&updatedAt)
			require.NoError(t, err)

			// Should be between before and after timestamps (with some tolerance)
			require.True(t, updatedAt.After(before.Add(-1*time.Second)) && updatedAt.Before(after.Add(1*time.Second)),
				"updatedAt should be close to now: before=%v, updatedAt=%v, after=%v", before, updatedAt, after)
		})
	})

	t.Run("Set same repository owner twice (should succeed)", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			repoID := uint64(11111)
			ownerID := uint64(22222)

			// Set the repository owner first time
			err = store.SetRepositoryOwner(ctx, repoID, ownerID)
			require.NoError(t, err)

			// Set the same repository owner again (should succeed with REPLACE)
			err = store.SetRepositoryOwner(ctx, repoID, ownerID)
			require.NoError(t, err)

			// Verify there's still only one record
			var count int
			err = s.QueryRowContext(ctx,
				"SELECT COUNT(*) FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID).Scan(&count)
			require.NoError(t, err)
			require.Equal(t, 1, count)
		})
	})

	t.Run("Update repository owner (one owner per repository)", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			repoID := uint64(33333)
			ownerID1 := uint64(44444)
			ownerID2 := uint64(55555)

			// Set first owner
			err = store.SetRepositoryOwner(ctx, repoID, ownerID1)
			require.NoError(t, err)

			// Verify first owner exists
			var count int
			err = s.QueryRowContext(ctx,
				"SELECT COUNT(*) FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID1).Scan(&count)
			require.NoError(t, err)
			require.Equal(t, 1, count)

			// Update to second owner (should replace, not add)
			err = store.SetRepositoryOwner(ctx, repoID, ownerID2)
			require.NoError(t, err)

			// Verify only one record exists for the repository
			err = s.QueryRowContext(ctx,
				"SELECT COUNT(*) FROM repository_owners WHERE repository_id = ?",
				repoID).Scan(&count)
			require.NoError(t, err)
			require.Equal(t, 1, count)

			// Verify the owner is now the second owner
			var actualOwnerID uint64
			err = s.QueryRowContext(ctx,
				"SELECT resource_owner_id FROM repository_owners WHERE repository_id = ?",
				repoID).Scan(&actualOwnerID)
			require.NoError(t, err)
			require.Equal(t, ownerID2, actualOwnerID)
		})
	})

	t.Run("Set with context cancellation", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			// Create a context that's already cancelled
			ctx, cancel := context.WithCancel(t.Context())
			cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			repoID := uint64(99999)
			ownerID := uint64(88888)

			// This should fail due to cancelled context
			err = store.SetRepositoryOwner(ctx, repoID, ownerID)
			require.Error(t, err)
			require.Contains(t, err.Error(), "context canceled")
		})
	})

	t.Run("Rejects zero values", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Test zero repository ID
			err = store.SetRepositoryOwner(ctx, 0, 12345)
			require.Error(t, err)
			require.Contains(t, err.Error(), "invalid repository ID")

			// Test zero owner ID
			err = store.SetRepositoryOwner(ctx, 12345, 0)
			require.Error(t, err)
			require.Contains(t, err.Error(), "invalid owner ID")

			// Test both zero
			err = store.SetRepositoryOwner(ctx, 0, 0)
			require.Error(t, err)
			require.Contains(t, err.Error(), "invalid repository ID")

			// Verify no records were inserted
			var count int
			err = s.QueryRowContext(ctx, "SELECT COUNT(*) FROM repository_owners").Scan(&count)
			require.NoError(t, err)
			require.Equal(t, 0, count, "No records should be inserted for invalid inputs")
		})
	})

	t.Run("Updates timestamp when replacing existing record", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			repoID := uint64(77777)
			ownerID := uint64(88888)

			// Manually insert a record with an old timestamp (5 days ago)
			oldTimestamp := time.Now().UTC().Add(-5 * 24 * time.Hour)
			_, err = s.ExecContext(ctx, `
				INSERT INTO repository_owners (repository_id, resource_owner_id, updated_at)
				VALUES (?, ?, ?)
			`, repoID, ownerID, oldTimestamp)
			require.NoError(t, err)

			// Verify the old timestamp is in place
			var initialUpdatedAt time.Time
			err = s.QueryRowContext(ctx,
				"SELECT updated_at FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID).Scan(&initialUpdatedAt)
			require.NoError(t, err)
			require.WithinDuration(t, oldTimestamp, initialUpdatedAt, 1*time.Second)

			// Now call SetRepositoryOwner which should update the timestamp
			before := time.Now().UTC()
			err = store.SetRepositoryOwner(ctx, repoID, ownerID)
			require.NoError(t, err)
			after := time.Now().UTC()

			// Verify the timestamp was updated to current time
			var newUpdatedAt time.Time
			err = s.QueryRowContext(ctx,
				"SELECT updated_at FROM repository_owners WHERE repository_id = ? AND resource_owner_id = ?",
				repoID, ownerID).Scan(&newUpdatedAt)
			require.NoError(t, err)

			// The new timestamp should be much newer than the old one
			require.True(t, newUpdatedAt.After(initialUpdatedAt.Add(4*24*time.Hour)),
				"new timestamp should be much newer than old timestamp")

			// The new timestamp should be close to current time
			require.True(t, newUpdatedAt.After(before.Add(-1*time.Second)) && newUpdatedAt.Before(after.Add(1*time.Second)),
				"new timestamp should be close to current time")
		})
	})
}

func TestSQLStore_AllProperties(t *testing.T) {
	db := fixtures.SetupDB(t, "configurations")

	globalTarget := model.GlobalTarget

	t.Run("Business target with hierarchical resolution", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			// Insert global entries
			insertConfigEntry(t, s, "global_config", "global_value", globalTarget, false)
			insertConfigEntry(t, s, "shared_config", "global_shared_value", globalTarget, false)

			// Insert business-specific entries
			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 123}
			insertConfigEntry(t, s, "business_config", "business_value", businessTarget, false)
			insertConfigEntry(t, s, "shared_config", "business_shared_value", businessTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			entries, err := store.AllProperties(ctx, businessTarget)

			require.NoError(t, err)
			require.Len(t, entries, 3)

			// Should get global-only config
			require.Equal(t, "global_value", entries["global_config"].Value)
			// Should get business-only config
			require.Equal(t, "business_value", entries["business_config"].Value)
			// Should get business value for shared config (business takes precedence)
			require.Equal(t, "business_shared_value", entries["shared_config"].Value)
		})
	})

	t.Run("Global target returns only global entries", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			// Insert global entries
			insertConfigEntry(t, s, "global_config1", "global_value1", globalTarget, false)
			insertConfigEntry(t, s, "global_config2", "global_value2", globalTarget, false)

			// Insert business entries (should not be returned for global target)
			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 456}
			insertConfigEntry(t, s, "business_config", "business_value", businessTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			entries, err := store.AllProperties(ctx, globalTarget)

			require.NoError(t, err)
			require.Len(t, entries, 2)

			require.Equal(t, "global_value1", entries["global_config1"].Value)
			require.Equal(t, "global_value2", entries["global_config2"].Value)
			// Should not contain business config
			require.NotContains(t, entries, "business_config")
		})
	})

	t.Run("No entries for target", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			// Insert entries for different targets
			insertConfigEntry(t, s, "other_config", "other_value", model.ConfigurationTarget{
				Type: model.Business,
				ID:   999,
			}, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Query for a business that has no entries
			entries, err := store.AllProperties(ctx, model.ConfigurationTarget{
				Type: model.Business,
				ID:   555,
			})

			require.NoError(t, err)
			require.Empty(t, entries)
		})
	})

	t.Run("Final entries are respected in hierarchy", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 789}
			globalTarget := model.GlobalTarget
			// Insert global entry marked as final
			insertConfigEntry(t, s, "final_config", "global_final_value", globalTarget, true)

			// Insert business entry for same config (should be ignored due to final flag)
			insertConfigEntry(t, s, "final_config", "business_value", businessTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			entries, err := store.AllProperties(ctx, businessTarget)

			require.NoError(t, err)
			require.Len(t, entries, 1)
			// Should get the global final value, not the business value
			require.Equal(t, "global_final_value", entries["final_config"].Value)
		})
	})

	t.Run("Other target types are handled", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			userTarget := model.ConfigurationTarget{Type: model.User, ID: 111}

			// Insert user entry
			insertConfigEntry(t, s, "user_config", "user_value", userTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			entries, err := store.AllProperties(ctx, userTarget)

			require.NoError(t, err)
			require.Len(t, entries, 1)
			require.Equal(t, "user_value", entries["user_config"].Value)
		})
	})

	t.Run("Empty result when no global entries exist for business", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			// Insert entries for other businesses, but no global entries
			insertConfigEntry(t, s, "other_business_config", "other_value", model.ConfigurationTarget{
				Type: model.Business,
				ID:   888,
			}, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Query for a business with no entries (and no global fallbacks)
			entries, err := store.AllProperties(ctx, model.ConfigurationTarget{
				Type: model.Business,
				ID:   777,
			})

			require.NoError(t, err)
			require.Empty(t, entries)
		})
	})
}

func TestSQLStore_ResolvedConfigsByTargetWithOwners(t *testing.T) {
	db := fixtures.SetupDB(t, "configurations")

	t.Run("Resolves configs across hierarchy with correct priority", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			// Create targets
			globalTarget := model.GlobalTarget
			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 100}
			userTarget := model.ConfigurationTarget{Type: model.User, ID: 200}
			repoTarget := model.ConfigurationTarget{Type: model.Repository, ID: 300}

			// Insert config at each level
			insertConfigEntry(t, s, "global_config", "global_value", globalTarget, false)
			insertConfigEntry(t, s, "business_config", "business_value", businessTarget, false)
			insertConfigEntry(t, s, "user_config", "user_value", userTarget, false)
			insertConfigEntry(t, s, "repo_config", "repo_value", repoTarget, false)

			// Insert override config that exists at multiple levels
			insertConfigEntry(t, s, "override_config", "global_override", globalTarget, false)
			insertConfigEntry(t, s, "override_config", "business_override", businessTarget, false)
			insertConfigEntry(t, s, "override_config", "user_override", userTarget, false)
			insertConfigEntry(t, s, "override_config", "repo_override", repoTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Query with all targets in hierarchy
			targets := []model.ConfigurationTarget{repoTarget, userTarget, businessTarget, globalTarget}
			entries, err := store.ResolvedConfigsByTargetWithOwners(ctx, targets)

			require.NoError(t, err)
			require.Len(t, entries, 5) // 4 unique configs + 1 override

			// Verify each config is present
			require.Equal(t, "global_value", entries["global_config"].Value)
			require.Equal(t, "business_value", entries["business_config"].Value)
			require.Equal(t, "user_value", entries["user_config"].Value)
			require.Equal(t, "repo_value", entries["repo_config"].Value)

			// Verify override_config uses the highest priority (repo)
			require.Equal(t, "repo_override", entries["override_config"].Value)
			require.Equal(t, model.Repository, entries["override_config"].Target.Type)
			require.Equal(t, uint64(300), entries["override_config"].Target.ID)
		})
	})

	t.Run("Respects final flag at lower priority level", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			globalTarget := model.GlobalTarget
			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 101}
			repoTarget := model.ConfigurationTarget{Type: model.Repository, ID: 301}

			// Insert a final config at global level
			insertConfigEntry(t, s, "final_config", "global_final_value", globalTarget, true)

			// Try to override at repo level (should be ignored due to final flag)
			insertConfigEntry(t, s, "final_config", "repo_override", repoTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			targets := []model.ConfigurationTarget{repoTarget, businessTarget, globalTarget}
			entries, err := store.ResolvedConfigsByTargetWithOwners(ctx, targets)

			require.NoError(t, err)
			require.Len(t, entries, 1)

			// Should use global value because it's marked as final
			require.Equal(t, "global_final_value", entries["final_config"].Value)
			require.True(t, entries["final_config"].Final)
			require.Equal(t, model.Global, entries["final_config"].Target.Type)
		})
	})

	t.Run("Returns empty map when no configs exist", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			targets := []model.ConfigurationTarget{
				{Type: model.Repository, ID: 999},
				{Type: model.User, ID: 888},
				model.GlobalTarget,
			}
			entries, err := store.ResolvedConfigsByTargetWithOwners(ctx, targets)

			require.NoError(t, err)
			require.Empty(t, entries)
		})
	})

	t.Run("Works with subset of hierarchy (no repo)", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			globalTarget := model.GlobalTarget
			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 102}
			userTarget := model.ConfigurationTarget{Type: model.User, ID: 202}

			insertConfigEntry(t, s, "global_config", "global_value", globalTarget, false)
			insertConfigEntry(t, s, "user_config", "user_value", userTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Query with only user, business, and global (no repo)
			targets := []model.ConfigurationTarget{userTarget, businessTarget, globalTarget}
			entries, err := store.ResolvedConfigsByTargetWithOwners(ctx, targets)

			require.NoError(t, err)
			require.Len(t, entries, 2)
			require.Equal(t, "user_value", entries["user_config"].Value)
			require.Equal(t, "global_value", entries["global_config"].Value)
		})
	})

	t.Run("Handles single target", func(t *testing.T) {
		db.ExecuteWithDBX(t, func(t *testing.T, s *sqlx.DB) {
			ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
			defer cancel()

			businessTarget := model.ConfigurationTarget{Type: model.Business, ID: 103}
			insertConfigEntry(t, s, "business_only", "business_value", businessTarget, false)

			store, err := NewStore(s, stats.NullStatter)
			require.NoError(t, err)

			// Query with only one target
			targets := []model.ConfigurationTarget{businessTarget}
			entries, err := store.ResolvedConfigsByTargetWithOwners(ctx, targets)

			require.NoError(t, err)
			require.Len(t, entries, 1)
			require.Equal(t, "business_value", entries["business_only"].Value)
		})
	})
}
