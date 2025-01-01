package blackbird

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_EncodeDecode(t *testing.T) {
	r := &SearchResults{
		Results: []*ResultDoc{
			{
				DocSHA: helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").Bytes(),
			},
		},
		NumRanked: 123,
		NextSHA:   gitaccess.NullObjectID.String(),
		docs:      map[gitaccess.ObjectID]*pb.GitDocumentMatch{gitaccess.NullObjectID: {}},
	}

	data, err := r.Marshal()
	require.NoError(t, err)

	var r2 SearchResults
	err = r2.Unmarshal(data)
	require.NoError(t, err)
	require.Len(t, r.Results, 1)
	require.Equal(t, helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").Bytes(), r.Results[0].DocSHA)
	require.Equal(t, r.NextSHA, r2.NextSHA)
	require.Equal(t, r.NumRanked, r2.NumRanked)
	require.Empty(t, r2.docs)
}

func Test_ShaRanges(t *testing.T) {
	start, end, err := determineSHARange("0000000000000000000000000000000000000000", 10, 10)
	require.NoError(t, err)
	require.Equal(t, "0000000000000000..ffffffffffffffff", fmt.Sprintf("%s..%s", start, end))

	start, end, err = determineSHARange("0000000000000000000000000000000000000000", 10, 100)
	require.NoError(t, err)
	require.Equal(t, "0000000000000000..1999999999999a00", fmt.Sprintf("%s..%s", start, end))

	start, end, err = determineSHARange("0000000000000000000000000000000000000000", 10, 1000)
	require.NoError(t, err)
	require.Equal(t, "0000000000000000..028f5c28f5c28f60", fmt.Sprintf("%s..%s", start, end))

	start, end, err = determineSHARange("2020202020202020202020202020202020202020", 10, 20)
	require.NoError(t, err)
	require.Equal(t, "2020202020202020..a020202020202020", fmt.Sprintf("%s..%s", start, end))
}
