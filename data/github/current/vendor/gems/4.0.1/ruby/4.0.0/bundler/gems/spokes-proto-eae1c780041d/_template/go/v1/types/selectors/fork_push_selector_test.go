package selectors

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func TestNewForkPushSelector(t *testing.T) {
	base := types.NewRepository(123)
	ref := types.NewReference([]byte("refs/heads/master"))
	before := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	after := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	refUpdate := types.NewReferenceUpdate(ref, before, after)
	fps := NewForkPushSelector(base, []*types.ReferenceUpdate{refUpdate})
	require.Equal(t, &ForkPushSelector{BaseRepository: base, ReferenceUpdates: []*types.ReferenceUpdate{refUpdate}}, fps)
}

func TestForkPushSelectorValidate(t *testing.T) {
	var nilPushSelector *PushSelector
	require.NoError(t, nilPushSelector.Validate())

	base := types.NewRepository(123)
	ref := types.NewReference([]byte("refs/heads/master"))
	before := types.NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	after := types.NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")

	refUpdate := types.NewReferenceUpdate(ref, before, after)

	valid := NewForkPushSelector(base, []*types.ReferenceUpdate{refUpdate})
	require.NoError(t, valid.Validate())

	invalidBase := &types.Repository{}
	invalidRefUpdate := types.NewReferenceUpdate(nil, nil, nil)

	var tests = []struct {
		name    string
		base    *types.Repository
		updates []*types.ReferenceUpdate
		err     string
	}{
		{"empty", nil, nil, "twirp error invalid_argument: base_repository is required"},
		{"invalid repository", invalidBase, nil, "twirp error invalid_argument: repository.id is required"},
		{"empty updates", base, nil, "twirp error invalid_argument: reference_updates is required"},
		{"invalid update", base, []*types.ReferenceUpdate{invalidRefUpdate}, "twirp error invalid_argument: reference is required"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fps := NewForkPushSelector(tt.base, tt.updates)
			assert.EqualError(t, fps.Validate(), tt.err)
		})
	}
}
