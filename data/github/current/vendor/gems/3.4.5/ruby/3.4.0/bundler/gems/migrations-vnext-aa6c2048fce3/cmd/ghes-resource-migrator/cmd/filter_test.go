package cmd

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_newResourceFilter(t *testing.T) {
	t.Run("new bloom filter", func(t *testing.T) {
		tmp := t.TempDir()
		f, err := newResourceFilter(tmp + "/bloomfilter")
		require.NoError(t, err)
		require.NotNil(t, f)
	})

	t.Run("element not found", func(t *testing.T) {
		tmp := t.TempDir()
		f, err := newResourceFilter(tmp + "/bloomfilter")
		require.NoError(t, err)
		require.NotNil(t, f)

		exists, err := f.contains(&v1.Resource{
			Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: "123"},
			},
		})
		require.NoError(t, err)
		assert.False(t, exists)
	})

	t.Run("element found", func(t *testing.T) {
		tmp := t.TempDir()
		f, err := newResourceFilter(tmp + "/bloomfilter")
		require.NoError(t, err)
		require.NotNil(t, f)

		err = f.add(&v1.Resource{
			Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: "123"},
			},
		})
		require.NoError(t, err)

		exists, err := f.contains(&v1.Resource{
			Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: "123"},
			},
		})
		require.NoError(t, err)
		assert.True(t, exists)
	})

	t.Run("save bloom filter", func(t *testing.T) {
		tmp := t.TempDir()
		f, err := newResourceFilter(tmp + "/bloomfilter")
		require.NoError(t, err)
		require.NotNil(t, f)

		err = f.add(&v1.Resource{
			Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: "123"},
			},
		})
		require.NoError(t, err)

		err = f.save()
		require.NoError(t, err)

		f2, err := newResourceFilter(tmp + "/bloomfilter")
		require.NoError(t, err)
		require.NotNil(t, f2)

		exists, err := f2.contains(&v1.Resource{
			Resource: &v1.Resource_Noop{
				Noop: &v1.Noop{ResourceId: "123"},
			},
		})
		require.NoError(t, err)
		assert.True(t, exists)
	})
}
