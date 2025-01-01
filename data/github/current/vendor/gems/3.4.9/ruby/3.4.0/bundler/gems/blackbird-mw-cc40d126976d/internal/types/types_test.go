package types

import (
	"fmt"
	"math"
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Scan(t *testing.T) {
	var tests = []struct {
		in  interface{}
		out NullRepoID
		err bool
	}{
		{
			in:  []byte("-1"),
			err: true,
		},
		{
			in:  []byte("0"),
			out: NullRepoID{RepoID: RepoID(0), Valid: true},
		},
		{
			in:  []byte("1"),
			out: NullRepoID{RepoID: RepoID(1), Valid: true},
		},
		{
			in:  []byte(strconv.Itoa(math.MaxUint32)),
			out: NullRepoID{RepoID: RepoID(math.MaxUint32), Valid: true},
		},
		{
			in:  []byte(strconv.Itoa(math.MaxUint32 + 1)),
			err: true,
		},
		{
			in:  nil,
			out: NullRepoID{},
		},
		{
			in:  int64(-1),
			err: true,
		},
		{
			in:  int64(0),
			out: NullRepoID{RepoID: RepoID(0), Valid: true},
		},
		{
			in:  int64(1),
			out: NullRepoID{RepoID: RepoID(1), Valid: true},
		},
		{
			in:  int64(math.MaxUint32),
			out: NullRepoID{RepoID: RepoID(math.MaxUint32), Valid: true},
		},
		{
			in:  int64(math.MaxUint32 + 1),
			err: true,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(fmt.Sprintf("%v", test.in), func(t *testing.T) {
			t.Parallel()
			nri := &NullRepoID{}
			err := nri.Scan(test.in)
			if test.err {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, test.out, *nri)
			}
		})
	}

}

func Test_RepoIDFromInt(t *testing.T) {
	ok := []int{0, math.MaxUint32}
	panics := []int{-1, math.MaxUint32 + 1}
	for _, ex := range ok {
		require.Equal(t, RepoID(ex), RepoIDFromInt(ex))
	}

	for _, ex := range panics {
		require.Panics(t, func() { RepoIDFromInt(ex) })
	}
}

func Test_RepoIDToInt32(t *testing.T) {
	require.Panics(t, func() { RepoID(math.MaxInt32 + 1).ToInt32() })
	require.Equal(t, int32(math.MaxInt32), RepoID(math.MaxInt32).ToInt32())
}
