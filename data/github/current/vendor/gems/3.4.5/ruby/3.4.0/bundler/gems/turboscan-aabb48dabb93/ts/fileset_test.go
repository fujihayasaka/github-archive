package ts_test

import (
	"encoding/json"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
)

func TestPathSet(t *testing.T) {
	for _, opts := range []struct {
		fs       ts.FileSet
		expected string
	}{
		{fs: ts.FileSet{}, expected: "[]"},
		{fs: ts.FileSet{"a/b/c/d.java": struct{}{}, "a/b/c/e.java": struct{}{}}, expected: `{"a/b/c":["d.java","e.java"]}`},
		{fs: ts.FileSet{"a/b/c/d.java": struct{}{}}, expected: `["a/b/c/d.java"]`},
		{fs: ts.FileSet{"a/b/1/d.java": struct{}{}, "a/b/2/d.java": struct{}{}, "a/b/1/e.java": struct{}{}, "a/b/2/e.java": struct{}{}}, expected: `{"a/b":{"1":["d.java","e.java"],"2":["d.java","e.java"]}}`},
		{fs: ts.FileSet{"a/b/1/d.java": struct{}{}, "a/e.java": struct{}{}}, expected: `{"a":{"b":["1/d.java"],"e.java":[]}}`},
		{fs: ts.FileSet{"a.java": struct{}{}, "b.java": struct{}{}}, expected: `["a.java","b.java"]`},
		{fs: ts.FileSet{"a/b/1/d.java": struct{}{}, "a/e.java": struct{}{}, "a/f.java": struct{}{}}, expected: `{"a":{"b":["1/d.java"],"e.java":[],"f.java":[]}}`},
	} {
		d, err := opts.fs.MarshalJSON()
		require.NoError(t, err)
		require.Equal(t, opts.expected, string(d))
		v := ts.FileSet{}
		require.NoError(t, json.Unmarshal(d, &v))
		require.Equal(t, opts.fs, v)
	}
}

func TestPathSet_Contains(t *testing.T) {
	set := make(ts.FileSet)
	set["file1"] = struct{}{}
	set["file2"] = struct{}{}
	require.Equal(t, true, set.Contains("file1"))
	require.Equal(t, true, set.Contains("file2"))
	require.Equal(t, false, set.Contains("file3"))
}
