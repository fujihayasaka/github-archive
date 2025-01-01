package archivalstore_test

import (
	"context"
	"fmt"
	"strings"
	"sync/atomic"
	"testing"

	"gocloud.dev/blob"
	"gocloud.dev/blob/memblob"

	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/stretchr/testify/require"

	v1 "github.com/github/turboscan/ts/monolith_twirp/enterprise/v1"

	"github.com/github/turboscan/ts/archivalstore"
)

type mockStorageAPI struct {
	LeastLoaded []string
}

func (m *mockStorageAPI) Hosts(context.Context, *v1.HostsRequest) (*v1.HostsResponse, error) {
	return &v1.HostsResponse{LeastLoaded: m.LeastLoaded}, nil
}

func TestArchivalStore_OneHost(t *testing.T) {
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		return store.TestMemoryStore()
	}, &mockStorageAPI{LeastLoaded: []string{"node1"}})

	path, err := as.Archive(context.Background(), strings.NewReader("{}"), "/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "//node1/test.sarif.gzip", path)
}

func TestArchivalStore_TwoHosts(t *testing.T) {
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		return store.TestMemoryStore()
	}, &mockStorageAPI{LeastLoaded: []string{"node1", "node2"}})

	path, err := as.Archive(context.Background(), strings.NewReader("{}"), "/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "//node1,node2/test.sarif.gzip", path)
}

func TestArchivalStore_NoHosts(t *testing.T) {
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		return store.TestMemoryStore()
	}, &mockStorageAPI{LeastLoaded: []string{}})

	_, err := as.Archive(context.Background(), strings.NewReader("{}"), "/test.sarif.gzip")
	require.ErrorContains(t, err, "no storage nodes available")
}

func TestArchivalStore_NewHosts(t *testing.T) {
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		return store.TestMemoryStore()
	}, &mockStorageAPI{LeastLoaded: []string{"node1", "node2"}})

	path, err := as.Archive(context.Background(), strings.NewReader("{}"), "//node3/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "//node1,node2/test.sarif.gzip", path)
}

func TestArchivalStore_Download_FirstTry(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		attempts.Add(1)
		require.Contains(t, []string{"node1", "node2"}, node)
		return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
			b := memblob.OpenBucket(nil)
			require.NoError(t, b.WriteAll(ctx, "/test.sarif.gzip", []byte("{}"), nil))
			return b, nil
		}, 1000)
	}, nil)

	buf, err := as.Download(ctx, "//node1,node2/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "{}", buf.String())
	require.Equal(t, int64(1), attempts.Load())
}

func TestArchivalStore_Download_Retry(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		if attempts.Add(1) == 1 {
			// return a bucket that has no entry
			return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
				return memblob.OpenBucket(nil), nil
			}, 1000)
		}
		require.Contains(t, []string{"node1", "node2"}, node)
		return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
			b := memblob.OpenBucket(nil)
			require.NoError(t, b.WriteAll(ctx, "/test.sarif.gzip", []byte("{}"), nil))
			return b, nil
		}, 1000)
	}, nil)

	buf, err := as.Download(ctx, "//node1,node2/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "{}", buf.String())
	require.Equal(t, int64(2), attempts.Load())
}

func TestArchivalStore_Download_Fail(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		attempts.Add(1)
		// return a bucket that has no entry
		return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
			return memblob.OpenBucket(nil), nil
		}, 1000)
	}, nil)

	_, err := as.Download(ctx, "//node1,node2/test.sarif.gzip")
	require.Error(t, err)
	require.Equal(t, int64(2), attempts.Load())
}

func TestArchivalStore_Download_OneHost(t *testing.T) {
	ctx := context.Background()
	var attempts atomic.Int64
	as := archivalstore.NewArchivalStore(func(node string) store.SarifStore {
		attempts.Add(1)
		require.Contains(t, []string{"node1"}, node)
		return store.NewSarifStoreWithOpenFunc(func(ctx context.Context) (*blob.Bucket, error) {
			b := memblob.OpenBucket(nil)
			require.NoError(t, b.WriteAll(ctx, "/test.sarif.gzip", []byte("{}"), nil))
			return b, nil
		}, 1000)
	}, nil)

	buf, err := as.Download(ctx, "//node1/test.sarif.gzip")
	require.NoError(t, err)
	require.Equal(t, "{}", buf.String())
	require.Equal(t, int64(1), attempts.Load())
}

func TestNewArchivalStoreFromConfig(t *testing.T) {
	st := store.TestMemoryStore()
	const storeType = "*archivalstore.archivalStore"
	// this should be a no-op as we are not in Enterprise
	{
		v, err := archivalstore.NewArchivalStoreFromConfig(st, &config.Config{})
		require.NoError(t, err)
		require.Equal(t, st, v)
		require.NotEqual(t, storeType, fmt.Sprintf("%T", v))
	}
	// this should be a no-op as we are not using S3
	{
		v, err := archivalstore.NewArchivalStoreFromConfig(st, &config.Config{AzureAccountName: "account", Environment: "enterprise"})
		require.NoError(t, err)
		require.Equal(t, st, v)
		require.NotEqual(t, storeType, fmt.Sprintf("%T", v))
	}
	// this should create an ArchivalStore
	{
		v, err := archivalstore.NewArchivalStoreFromConfig(st, &config.Config{GitHubTwirpHMACKey: "hmac", Environment: "enterprise"})
		require.NoError(t, err)
		require.NotEqual(t, st, v)
		require.Equal(t, storeType, fmt.Sprintf("%T", v))
	}
}
