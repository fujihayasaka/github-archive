package store

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"

	_ "gocloud.dev/blob"

	goconfig "github.com/github/go-config"
	"github.com/github/turboscan/ts/config"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

// requireFile opens the file with the given name within the testdata/ folder.
// Returns the file descriptor.
func requireFile(t *testing.T, name string) *os.File {
	t.Helper()
	path := filepath.Join("..", "testdata", name)
	f, err := os.Open(path)
	require.NoError(t, err)
	return f
}

// requireUpload uploads data into given path and checks for no error
func requireUpload(t *testing.T, ctx context.Context, ss SarifStore, data []byte, path string) {
	t.Helper()
	err := ss.Upload(ctx, bytes.NewReader(data), path)
	require.NoError(t, err)
}

func neededBufferCapacity(s SarifStore) int {
	return int(s.MaxSarifSize() + bytes.MinRead)
}

func storageEngine() config.StorageEngine {
	return config.STORAGE_MEMORY
}

func TestUploadDownload(t *testing.T) {
	ctx := context.Background()

	ss := NewSarifStore(storageEngine(), &config.Config{MaxSarifSize: 3 + 1})
	require.NoError(t, ss.Open(ctx))
	defer ss.Close(ctx)

	data := []byte("abc")
	path := "testing/" + uuid.NewString()
	requireUpload(t, ctx, ss, data, path)

	buf, err := ss.Download(ctx, path)
	require.NoError(t, err)
	require.Equal(t, data, buf.Bytes())
	require.LessOrEqual(t, buf.Cap(), neededBufferCapacity(ss))

	// Should create another file
	path = "testing/" + uuid.NewString()
	requireUpload(t, ctx, ss, []byte("42"), path)

	buf2, err := ss.Download(ctx, path)
	require.NoError(t, err)
	require.NotEqual(t, data, buf2.Bytes())
	require.LessOrEqual(t, buf2.Cap(), neededBufferCapacity(ss))
}

func TestDecodeCompressed(t *testing.T) {
	ctx := context.Background()

	f := requireFile(t, "example.sarif")
	defer f.Close()

	info, err := f.Stat()
	require.NoError(t, err)

	ss := NewSarifStore(storageEngine(), &config.Config{MaxSarifSize: goconfig.Byte(1 + info.Size())})
	require.NoError(t, ss.Open(ctx))
	defer ss.Close(ctx)

	data, err := io.ReadAll(f)
	require.NoError(t, err)

	path := "testing/" + uuid.NewString()
	requireUpload(t, ctx, ss, data, path)

	buf, err := ss.Download(ctx, path)
	require.NoError(t, err)
	require.Equal(t, data, buf.Bytes())
	require.LessOrEqual(t, buf.Cap(), neededBufferCapacity(ss))
}

func TestUnexpectedEOFError(t *testing.T) {
	f := requireFile(t, "corrupt.sarif.gz")
	defer f.Close()

	erroringReader := &erroringReader{Reader: NewErrorLimitReader(f, 10, io.ErrUnexpectedEOF)}

	var buf bytes.Buffer
	err := uncompress(&buf, erroringReader, 0)
	require.Error(t, err)
	require.True(t, errors.Is(err, io.ErrUnexpectedEOF))

	require.Error(t, erroringReader.Error())
}

func TestUncompressError(t *testing.T) {
	f := requireFile(t, "corrupt.sarif.gz")
	defer f.Close()

	erroringReader := &erroringReader{Reader: f}

	var buf bytes.Buffer

	err := uncompress(&buf, erroringReader, 0)
	require.Error(t, err)
	require.True(t, errors.Is(err, io.ErrUnexpectedEOF))

	require.NoError(t, erroringReader.Error())
}

func TestCorruptGz(t *testing.T) {
	ctx := context.Background()

	ss := NewSarifStore(storageEngine(), &config.Config{MaxSarifSize: 0})
	require.NoError(t, ss.Open(ctx))
	defer ss.Close(ctx)

	f := requireFile(t, "corrupt.sarif.gz")
	defer f.Close()

	data, err := io.ReadAll(f)
	require.NoError(t, err)

	path := "testing/sarif.gz"
	requireUpload(t, ctx, ss, data, path)

	_, err = ss.Download(ctx, path)
	require.Error(t, err)
	require.Equal(t, "failed to copy to output from the buffer: failed decompressing file: unexpected EOF", err.Error())
}

func TestUncompressGz(t *testing.T) {
	ctx := context.Background()

	ss := NewSarifStore(storageEngine(), &config.Config{MaxSarifSize: 0})
	require.NoError(t, ss.Open(ctx))
	defer ss.Close(ctx)

	f := requireFile(t, "example.sarif.gz")
	defer f.Close()

	data, err := io.ReadAll(f)
	require.NoError(t, err)

	path := "testing/sarif.gz"
	requireUpload(t, ctx, ss, data, path)

	buf, err := ss.Download(ctx, path)
	require.NoError(t, err)

	d := requireFile(t, "example.sarif")
	defer d.Close()
	data, err = io.ReadAll(d)
	require.NoError(t, err)
	require.Equal(t, data, buf.Bytes())
}

func TestMaxSarifSizeExceeded(t *testing.T) {
	ctx := context.Background()

	const limit = 1024 * 1024

	ss := NewSarifStore(storageEngine(), &config.Config{MaxSarifSize: limit})
	require.NoError(t, ss.Open(ctx))
	defer ss.Close(ctx)

	data := make([]byte, 5*limit)
	path := "testing/" + uuid.NewString()
	requireUpload(t, ctx, ss, data, path)

	buf, err := ss.Download(ctx, path)
	// We've hit the limit
	require.ErrorIs(t, err, ErrMaximumSizeExceeded)
	// But we did not exceed the buffer size limit when doing so
	require.NotNil(t, buf)
	require.LessOrEqual(t, buf.Cap(), neededBufferCapacity(ss))
}
