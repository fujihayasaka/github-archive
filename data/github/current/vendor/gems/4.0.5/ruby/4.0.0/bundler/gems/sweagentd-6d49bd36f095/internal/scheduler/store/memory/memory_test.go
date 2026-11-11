package memory

import (
	"context"
	"testing"

	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func intPtr(i int) *int { return &i }

func seedRecord(t *testing.T, store *Store, scopeID int64) *schedulerstore.IntervalTriggerRecord {
	t.Helper()
	rec, err := store.Upsert(context.Background(), &schedulerstore.IntervalTriggerRecord{
		ID:           uuid.NewString(),
		Scope:        schedulerstore.ScopeRepository,
		ScopeID:      scopeID,
		AgentID:      uuid.NewString(),
		IntervalType: schedulerstore.IntervalTypeDaily,
	})
	require.NoError(t, err)
	return rec
}

func TestPatchTrigger_SetsAnchorFields(t *testing.T) {
	ctx := context.Background()
	store := NewStore()
	rec := seedRecord(t, store, 42)
	require.Nil(t, rec.AnchorHourUTC)
	require.Nil(t, rec.AnchorDayOfWeek)

	_, err := store.PatchTrigger(ctx, 42, rec.ID, schedulerstore.IntervalTriggerPatch{
		AnchorHourUTC:   intPtr(8),
		AnchorDayOfWeek: intPtr(2),
	})
	require.NoError(t, err)

	got, err := store.Get(ctx, 42, rec.ID)
	require.NoError(t, err)
	require.NotNil(t, got.AnchorHourUTC)
	require.NotNil(t, got.AnchorDayOfWeek)
	assert.Equal(t, 8, *got.AnchorHourUTC)
	assert.Equal(t, 2, *got.AnchorDayOfWeek)
}

func TestPatchTrigger_UpdatesExistingAnchorFields(t *testing.T) {
	ctx := context.Background()
	store := NewStore()

	// Seed a record that already has an anchor (Sunday 9am).
	rec, err := store.Upsert(ctx, &schedulerstore.IntervalTriggerRecord{
		ID:              uuid.NewString(),
		Scope:           schedulerstore.ScopeRepository,
		ScopeID:         42,
		AgentID:         uuid.NewString(),
		IntervalType:    schedulerstore.IntervalTypeWeekly,
		AnchorHourUTC:   intPtr(9),
		AnchorDayOfWeek: intPtr(0),
	})
	require.NoError(t, err)

	// Patch to Wednesday 21:00.
	_, err = store.PatchTrigger(ctx, 42, rec.ID, schedulerstore.IntervalTriggerPatch{
		AnchorHourUTC:   intPtr(21),
		AnchorDayOfWeek: intPtr(3),
	})
	require.NoError(t, err)

	got, err := store.Get(ctx, 42, rec.ID)
	require.NoError(t, err)
	assert.Equal(t, 21, *got.AnchorHourUTC)
	assert.Equal(t, 3, *got.AnchorDayOfWeek)
}

func TestPatchTrigger_LeavesAnchorFieldsUnchangedIfNotPatched(t *testing.T) {
	ctx := context.Background()
	store := NewStore()

	rec, err := store.Upsert(ctx, &schedulerstore.IntervalTriggerRecord{
		ID:            uuid.NewString(),
		Scope:         schedulerstore.ScopeRepository,
		ScopeID:       42,
		AgentID:       uuid.NewString(),
		IntervalType:  schedulerstore.IntervalTypeDaily,
		AnchorHourUTC: intPtr(8),
	})
	require.NoError(t, err)

	// Patch only an unrelated sync field.
	actorLogin := "new-actor"
	_, err = store.PatchTrigger(ctx, 42, rec.ID, schedulerstore.IntervalTriggerPatch{
		ActorLogin: &actorLogin,
	})
	require.NoError(t, err)

	got, err := store.Get(ctx, 42, rec.ID)
	require.NoError(t, err)
	require.NotNil(t, got.AnchorHourUTC)
	assert.Equal(t, 8, *got.AnchorHourUTC, "unrelated patch must not touch anchor fields")
}

func TestPatchTrigger_AnchorFieldsAreDeepCopiedOnRead(t *testing.T) {
	// Defensive: confirms that mutating a returned record's anchor doesn't reach back into
	// the store's copy via shared pointers.
	ctx := context.Background()
	store := NewStore()
	rec := seedRecord(t, store, 42)

	_, err := store.PatchTrigger(ctx, 42, rec.ID, schedulerstore.IntervalTriggerPatch{
		AnchorHourUTC: intPtr(8),
	})
	require.NoError(t, err)

	first, err := store.Get(ctx, 42, rec.ID)
	require.NoError(t, err)

	// Mutate the returned pointer.
	*first.AnchorHourUTC = 99

	second, err := store.Get(ctx, 42, rec.ID)
	require.NoError(t, err)
	require.NotNil(t, second.AnchorHourUTC)
	assert.Equal(t, 8, *second.AnchorHourUTC, "store must deep-copy *int anchor fields on read")
}
