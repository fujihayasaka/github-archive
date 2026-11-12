package types

import (
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

func Test_CreateNWO(t *testing.T) {
	tenant := &pb.Tenant{Shortcode: "bigco"}

	nwo, err := NewNWO("a/b")
	require.NoError(t, err)
	require.Equal(t, "a", nwo.Owner().String())
	require.Equal(t, "b", nwo.Name())
	require.Equal(t, "a/b", nwo.String())
	require.Equal(t, "a/b", nwo.NameWithDisplayOwner(nil))
	require.Equal(t, "a/b", nwo.NameWithUniqueOwner(nil))
	require.Equal(t, "a/b", nwo.NameWithDisplayOwner(tenant))
	require.Equal(t, "a_bigco/b", nwo.NameWithUniqueOwner(tenant))

	nwo, err = NewNWO("a_code/b")
	require.NoError(t, err)
	require.Equal(t, "a_code", nwo.Owner().String())
	require.Equal(t, "b", nwo.Name())
	require.Equal(t, "a_code/b", nwo.String())
	require.Equal(t, "a_code/b", nwo.NameWithDisplayOwner(nil))
	require.Equal(t, "a_code/b", nwo.NameWithUniqueOwner(nil))
	require.Equal(t, "a_code/b", nwo.NameWithDisplayOwner(tenant))
	require.Equal(t, "a_code_bigco/b", nwo.NameWithUniqueOwner(tenant))

	// NB: No longer a valid login, but some dotcom users have logins like this
	nwo, err = NewNWO("a_b_c/x")
	require.NoError(t, err)
	require.Equal(t, "a_b_c", nwo.Owner().String())
	require.Equal(t, "x", nwo.Name())
	require.Equal(t, "a_b_c/x", nwo.String())
	require.Equal(t, "a_b_c/x", nwo.NameWithDisplayOwner(nil))
	require.Equal(t, "a_b_c/x", nwo.NameWithUniqueOwner(nil))
	require.Equal(t, "a_b_c/x", nwo.NameWithDisplayOwner(tenant))
	require.Equal(t, "a_b_c_bigco/x", nwo.NameWithUniqueOwner(tenant))

	// NB: This one already has the tenant suffix
	nwo, err = NewNWO("a_bigco/x")
	require.NoError(t, err)
	require.Equal(t, "a_bigco", nwo.Owner().String())
	require.Equal(t, "x", nwo.Name())
	require.Equal(t, "a_bigco/x", nwo.String())
	require.Equal(t, "a_bigco/x", nwo.NameWithDisplayOwner(nil))
	require.Equal(t, "a_bigco/x", nwo.NameWithUniqueOwner(nil))
	require.Equal(t, "a/x", nwo.NameWithDisplayOwner(tenant))
	require.Equal(t, "a_bigco/x", nwo.NameWithUniqueOwner(tenant))
}

func Test_ErrorsWithInvalidNWO(t *testing.T) {
	for _, nwo := range []string{"", "_", "a", "a_b_c", "a/", "/b", "a/b/c"} {
		_, err := NewNWO(nwo)
		require.EqualError(t, err, fmt.Sprintf("%q is not a valid repo nwo", nwo), fmt.Sprintf("nwo = %q", nwo))
	}

	for _, nwo := range []string{"_/c"} {
		_, err := NewNWO(nwo)
		require.EqualError(t, err, fmt.Sprintf("%q is not a valid login", strings.Split(nwo, "/")[0]), fmt.Sprintf("nwo = %q", nwo))
	}
}

func Test_ZeroValueNWO(t *testing.T) {
	require.Equal(t, "", NWO{}.String())
}

func Test_CreatePanicsWithInvalidNWO(t *testing.T) {
	require.Panics(t, func() { NWOFromString("") })
	require.Panics(t, func() { NWOFromString("a") })
	require.Panics(t, func() { NWOFromString("a/") })
	require.Panics(t, func() { NWOFromString("/b") })
	require.Panics(t, func() { NWOFromString("a/b/") })
	require.Panics(t, func() { NWOFromString("a/b/c") })
}

func Test_IsValidNWO(t *testing.T) {
	require.True(t, IsValidRepoNWO("a/b"))
	require.True(t, IsValidRepoNWO("a_b/c"))
	require.True(t, IsValidRepoNWO("a-b/c"))
	require.False(t, IsValidRepoNWO("a"))
	require.False(t, IsValidRepoNWO("a/"))
	require.False(t, IsValidRepoNWO("/b"))
	require.False(t, IsValidRepoNWO("a/b/"))
	require.False(t, IsValidRepoNWO("a/b/c"))
}

func Test_EqualNWO(t *testing.T) {
	require.True(t, NWOFromString("a/b").Equal(NWOFromString("a/b")))
	require.True(t, NWOFromString("A/b").Equal(NWOFromString("a/b")))
	require.True(t, NWOFromString("A/B").Equal(NWOFromString("a/b")))
	require.True(t, NWOFromString("a/B").Equal(NWOFromString("a/b")))
	require.False(t, NWOFromString("a/b").Equal(NWOFromString("c/b")))
	require.False(t, NWOFromString("a/b").Equal(NWOFromString("a/x")))
}
