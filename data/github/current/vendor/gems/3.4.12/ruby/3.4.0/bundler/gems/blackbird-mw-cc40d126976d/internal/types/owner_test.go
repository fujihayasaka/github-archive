package types

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

func Test_CreateOwner(t *testing.T) {
	tenant := &pb.Tenant{Shortcode: "bigco"}

	o, err := NewOwner("a")
	require.NoError(t, err)
	require.Equal(t, "a", o.String())
	require.Equal(t, "a", o.DisplayLogin(nil))
	require.Equal(t, "a", o.UniqueLogin(nil))
	require.Equal(t, "a", o.DisplayLogin(tenant))
	require.Equal(t, "a_bigco", o.UniqueLogin(tenant))

	o, err = NewOwner("a_code")
	require.NoError(t, err)
	require.Equal(t, "a_code", o.String())
	require.Equal(t, "a_code", o.DisplayLogin(nil))
	require.Equal(t, "a_code", o.UniqueLogin(nil))
	require.Equal(t, "a_code", o.DisplayLogin(tenant))
	require.Equal(t, "a_code_bigco", o.UniqueLogin(tenant))

	// NB: No longer a valid login, but some dotcom users have logins like this
	o, err = NewOwner("a_b_c")
	require.NoError(t, err)
	require.Equal(t, "a_b_c", o.String())
	require.Equal(t, "a_b_c", o.DisplayLogin(nil))
	require.Equal(t, "a_b_c", o.UniqueLogin(nil))
	require.Equal(t, "a_b_c", o.DisplayLogin(tenant))
	require.Equal(t, "a_b_c_bigco", o.UniqueLogin(tenant))

	// NB: This one already has the tenant suffix
	o, err = NewOwner("a_bigco")
	require.NoError(t, err)
	require.Equal(t, "a_bigco", o.String())
	require.Equal(t, "a_bigco", o.DisplayLogin(nil))
	require.Equal(t, "a_bigco", o.UniqueLogin(nil))
	require.Equal(t, "a", o.DisplayLogin(tenant))
	require.Equal(t, "a_bigco", o.UniqueLogin(tenant))
}

func Test_ErrorsWithInvalidOwner(t *testing.T) {
	for _, login := range []string{"", "_", "a/", "/b"} {
		_, err := NewOwner(login)
		require.EqualError(t, err, fmt.Sprintf("%q is not a valid login", login))
	}
}

func Test_EqualOwner(t *testing.T) {
	a, err := NewOwner("a")
	require.NoError(t, err)
	b, err := NewOwner("a")
	require.NoError(t, err)
	require.True(t, a.Equal(b))
}
