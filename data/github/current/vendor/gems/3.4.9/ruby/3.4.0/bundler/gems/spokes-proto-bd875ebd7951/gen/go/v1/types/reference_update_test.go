package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var (
	before = NewObjectID("f6cda0f92fb54061b209e64c97361f78c870970a")
	after  = NewObjectID("6a157b2d1e2fa7258317656940984a79fa01f533")
)

func TestNewReferenceUpdate(t *testing.T) {
	ref := NewReference([]byte("refs/heads/default"))
	ru := NewReferenceUpdate(ref, before, after)
	require.Equal(t, &ReferenceUpdate{Reference: ref, Before: before, After: after}, ru)
}

func TestReferenceUpdateValidate(t *testing.T) {
	var nilRefUpdate *ReferenceUpdate
	require.NoError(t, nilRefUpdate.Validate())

	ref := NewReference([]byte("refs/heads/default"))

	valid := NewReferenceUpdate(ref, before, after)
	require.NoError(t, valid.Validate())

	invalid := NewObjectID("")

	var tests = []struct {
		name   string
		ref    *Reference
		before *ObjectID
		after  *ObjectID
		err    string
	}{
		{"empty", nil, nil, nil, "twirp error invalid_argument: reference is required"},
		{"missing before and after", ref, nil, nil, "twirp error invalid_argument: reference_update is invalid as before and after are both nil, only one of them can be nil at any time"},
		{"invalid before", ref, invalid, after, "twirp error invalid_argument: reference_update.before contains an invalid object id "},
		{"invalid after", ref, before, invalid, "twirp error invalid_argument: reference_update.after contains an invalid object id "},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ru := NewReferenceUpdate(tt.ref, tt.before, tt.after)
			assert.EqualError(t, ru.Validate(), tt.err)
		})
	}
}
