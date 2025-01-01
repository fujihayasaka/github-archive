package store

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"testing"

	goconfig "github.com/github/go-config"
	"github.com/github/turboscan/ts/config"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

// zeroReader is a cross-platform implementation of /dev/zero
type zeroReader struct {
}

func (*zeroReader) Read(data []byte) (count int, err error) {
	// go optimizes zero allocation in a loop to a memset
	for idx := range data {
		data[idx] = 0
	}
	return len(data), nil
}

func TestZipBomb(t *testing.T) {
	// keep the tests fast by using a low maximum size
	// this still exercises the code in the same way as a larger cutoff
	const MaxSarifSize int64 = 100

	ctx := context.Background()

	ss := NewSarifStore(config.STORAGE_MEMORY, &config.Config{MaxSarifSize: goconfig.Byte(MaxSarifSize)})
	err := ss.Open(ctx)
	require.NoError(t, err)
	defer ss.Close(ctx)

	buffer := &bytes.Buffer{}
	zipbomb := gzip.NewWriter(buffer)
	_, err = io.Copy(zipbomb, io.LimitReader(&zeroReader{}, MaxSarifSize+1))
	require.NoError(t, err)
	zipbomb.Close()

	// the zipbomb created above looks reasonable from the outside but trips the
	// MaximumSizeExceeded error
	const ReasonableZipSize = 512 * 1024 // 0.5MB
	require.Greater(t, buffer.Len(), 0)
	require.Less(t, buffer.Len(), ReasonableZipSize)

	path := "testing/zipbomb.sarif.gz"
	requireUpload(t, ctx, ss, buffer.Bytes(), path)

	_, err = ss.Download(ctx, path)
	require.Error(t, err)
	require.True(t, errors.Is(err, ErrMaximumSizeExceeded))

	// the error is wrapped in an UncompressError to signal that it is not
	// transient
	var uerr *UncompressError
	require.True(t, errors.As(err, &uerr))
}
