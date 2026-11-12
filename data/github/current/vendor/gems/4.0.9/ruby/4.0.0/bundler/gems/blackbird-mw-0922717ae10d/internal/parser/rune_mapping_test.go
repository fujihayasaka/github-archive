package parser

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRuneMapping(t *testing.T) {
	// Contains no unicode, so no mappings are generated
	r := NewRuneMapping("asdf")
	require.Equal(t, RuneMapping{
		offsets:   []uint32{},
		byteCount: 4,
		runeCount: 4,
	}, r)

	q := "你好吗"
	r = NewRuneMapping(q)
	require.Equal(t, RuneMapping{
		offsets:   []uint32{1, 1, 2, 2},
		runeCount: 3,
		byteCount: 9,
	}, r)

	require.Equal(t, uint32(0), r.GetBytePos(0))
	require.Equal(t, uint32(3), r.GetBytePos(1))
	require.Equal(t, uint32(6), r.GetBytePos(2))
	require.Equal(t, uint32(9), r.GetBytePos(3))

	require.Equal(t, "你", q[r.GetBytePos(0):r.GetBytePos(1)])
	require.Equal(t, "好", q[r.GetBytePos(1):r.GetBytePos(2)])
	require.Equal(t, "吗", q[r.GetBytePos(2):r.GetBytePos(3)])

	q = "까투리 매추래기 새끼들도 깃들이어 오는 소리…"
	r = NewRuneMapping(q)
	require.Equal(t, "까투리 ", q[r.GetBytePos(0):r.GetBytePos(4)])
	require.Equal(t, "매추래기 ", q[r.GetBytePos(4):r.GetBytePos(9)])
}
