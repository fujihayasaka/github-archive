// Package compress allows clients to compress/decompress payloads using different encoding algorithms.
package compress

import (
	"github.com/github/notifyd/internal/pkg/compress/zlib"
	"github.com/github/notifyd/internal/pkg/errors"
)

// Encoding identifies the compression encoding.
type Encoding string

// Supported encodings.
const (
	// Deflate is the standard zlib compression algorithm.
	Deflate Encoding = "deflate"
)

type compressor func([]byte) ([]byte, error)
type decompressor func([]byte) ([]byte, error)

// Compress data using one of the supported encodings.
func Compress(enc Encoding, src []byte) ([]byte, error) {
	compress, err := newCompressor(enc)
	if err != nil {
		return nil, err
	}

	return compress(src)
}

// Decompress data encoding with some supported encoding.
func Decompress(enc Encoding, src []byte) ([]byte, error) {
	decompress, err := newDecompressor(enc)
	if err != nil {
		return nil, err
	}

	return decompress(src)
}

func newCompressor(enc Encoding) (compressor, error) {
	switch enc {
	case Deflate:
		return zlib.Deflate, nil
	default:
		return nil, errors.Newf("Unknown encoding algorithm %s", enc)
	}
}

func newDecompressor(enc Encoding) (decompressor, error) {
	switch enc {
	case Deflate:
		return zlib.Inflate, nil
	default:
		return nil, errors.Newf("Unknown encoding algorithm %s", enc)
	}
}
