package compress

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_DeflateRoundtrip(t *testing.T) {
	r := require.New(t)

	message := []byte("hello, world\n")

	deflated, err := Compress(Deflate, message)
	r.NoError(err)
	r.NotEqual(message, deflated)

	inflated, err := Decompress(Deflate, deflated)
	r.NoError(err)
	r.Equal(message, inflated)
}

func Test_UnknownEncoding(t *testing.T) {
	r := require.New(t)

	_, err := Compress(Encoding("unknown"), []byte(""))
	r.Error(err)
}
