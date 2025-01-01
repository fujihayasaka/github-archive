package tenancy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_TenantContext_SingleTenant(t *testing.T) {
	ctx := context.Background()

	ctx = ContextWithTenant(ctx, NewSingleTenant())
	tenant, err := FromContext(ctx)

	require.NoError(t, err)
	require.IsType(t, SingleTenant{}, tenant)
}

func Test_TenantContext_MultiTenant(t *testing.T) {
	ctx := context.Background()

	multi := NewMultiTenant().WithSlug("avocado").WithID(int64(123))

	ctx = ContextWithTenant(ctx, multi)
	tenant, err := FromContext(ctx)

	require.NoError(t, err)
	require.IsType(t, MultiTenant{}, tenant)
	require.Equal(t, "avocado", tenant.Slug())
	require.Equal(t, int64(123), tenant.ID())
}
