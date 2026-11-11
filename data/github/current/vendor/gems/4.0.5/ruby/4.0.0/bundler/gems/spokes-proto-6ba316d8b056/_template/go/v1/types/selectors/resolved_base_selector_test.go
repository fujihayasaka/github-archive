package selectors

import (
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

func TestNewResolvedBaseSelector(t *testing.T) {
	rs := NewResolvedBaseSelector()
	require.Equal(t, &ResolvedBaseSelector{}, rs)
}

func TestNewResolvedBaseSelectorWithObjectIDs(t *testing.T) {
	oid1 := types.NewObjectID("1234567890123456789012345678901234567890")
	oid2 := types.NewObjectID("abcdefabcdefabcdefabcdefabcdefabcdefabcd")
	
	rs := NewResolvedBaseSelectorWithObjectIDs(oid1, oid2)
	require.Equal(t, oid1, rs.GetObjectId1())
	require.Equal(t, oid2, rs.GetObjectId2())
}

func TestNewResolvedBaseSelectorWithRepoObjectIDs(t *testing.T) {
	repo := types.NewRepository(123)
	oid1 := types.NewObjectID("1234567890123456789012345678901234567890")
	oid2 := types.NewObjectID("abcdefabcdefabcdefabcdefabcdefabcdefabcd")
	
	repoOid1 := NewRepoObjectIDSelector(repo, oid1)
	repoOid2 := NewRepoObjectIDSelector(repo, oid2)
	
	rs := NewResolvedBaseSelectorWithRepoObjectIDs(repoOid1, repoOid2)
	require.Equal(t, repoOid1, rs.GetRepoObjectId1())
	require.Equal(t, repoOid2, rs.GetRepoObjectId2())
}

func TestResolvedBaseSelectorValidate(t *testing.T) {
	var nilSelector *ResolvedBaseSelector
	require.NoError(t, nilSelector.Validate())

	// Valid cases
	validOid1 := types.NewObjectID("1234567890123456789012345678901234567890")
	validOid2 := types.NewObjectID("abcdefabcdefabcdefabcdefabcdefabcdefabcd")
	
	valid := NewResolvedBaseSelectorWithObjectIDs(validOid1, validOid2)
	require.NoError(t, valid.Validate())

	// Valid with root selector for oid1
	validWithRoot := &ResolvedBaseSelector{
		Oid1: &ResolvedBaseSelector_RootSelector1{RootSelector1: NewRootSelector()},
		Oid2: &ResolvedBaseSelector_ObjectId2{ObjectId2: validOid2},
	}
	require.NoError(t, validWithRoot.Validate())

	// Valid with optional base_oid
	validWithBase := &ResolvedBaseSelector{
		Oid1:    &ResolvedBaseSelector_ObjectId1{ObjectId1: validOid1},
		Oid2:    &ResolvedBaseSelector_ObjectId2{ObjectId2: validOid2},
		BaseOid: &ResolvedBaseSelector_BaseObjectId{BaseObjectId: validOid1},
	}
	require.NoError(t, validWithBase.Validate())

	// Invalid cases - missing oid1
	invalidMissingOid1 := &ResolvedBaseSelector{
		Oid2: &ResolvedBaseSelector_ObjectId2{ObjectId2: validOid2},
	}
	err := invalidMissingOid1.Validate()
	require.Error(t, err)
	require.Equal(t, twirp.RequiredArgumentError("oid1"), err)

	// Invalid cases - missing oid2
	invalidMissingOid2 := &ResolvedBaseSelector{
		Oid1: &ResolvedBaseSelector_ObjectId1{ObjectId1: validOid1},
	}
	err = invalidMissingOid2.Validate()
	require.Error(t, err)
	require.Equal(t, twirp.RequiredArgumentError("oid2"), err)

	// Invalid cases - invalid object ID
	invalidOid := types.NewObjectID("invalid")
	invalidWithBadOid := &ResolvedBaseSelector{
		Oid1: &ResolvedBaseSelector_ObjectId1{ObjectId1: invalidOid},
		Oid2: &ResolvedBaseSelector_ObjectId2{ObjectId2: validOid2},
	}
	err = invalidWithBadOid.Validate()
	require.Error(t, err)
}
