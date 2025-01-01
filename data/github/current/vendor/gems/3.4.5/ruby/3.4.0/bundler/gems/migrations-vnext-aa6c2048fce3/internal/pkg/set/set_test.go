package set

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_FromSlice(t *testing.T) {
	tests := map[string]struct {
		has   []int
		wants []int
	}{
		"should convert a slice to set": {
			has:   []int{1, 2, 3, 2},
			wants: []int{1, 2, 3},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := FromSlice(test.has)

			for _, want := range test.wants {
				assert.True(t, s.Contains(want))
			}
		})
	}
}

func Test_New(t *testing.T) {
	tests := map[string]struct {
		wants []int
	}{
		"should create a new set with no values": {},
		"should create a new set with one value": {
			wants: []int{1},
		},
		"should create a new set with multiple values": {
			wants: []int{1, 2, 3},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := New(test.wants...)

			for _, want := range test.wants {
				assert.Contains(t, s, want)
			}
		})
	}
}

func TestSet_Add(t *testing.T) {
	tests := map[string]struct {
		gets  []int
		wants []int
	}{
		"should insert a new value into an empty set": {
			gets:  []int{1},
			wants: []int{1},
		},
		"should insert multiple values into an empty set": {
			gets: []int{1, 2},
		},
		"should not contain duplicates": {
			gets:  []int{1, 1, 2},
			wants: []int{1, 2},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := New[int]()
			s.Add(test.gets...)

			for _, want := range test.wants {
				assert.Contains(t, s, want)
			}
		})
	}
}

func TestSet_Contains(t *testing.T) {
	tests := map[string]struct {
		gets  int
		has   []int
		wants bool
	}{
		"should return false when value is not in slice": {
			gets:  2,
			has:   []int{1},
			wants: false,
		},
		"should return true when value is in slice": {
			gets:  1,
			has:   []int{1},
			wants: true,
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := New[int]()
			s.Add(test.has...)

			assert.Equal(t, test.wants, s.Contains(test.gets))
		})
	}
}

func TestSet_Remove(t *testing.T) {
	tests := map[string]struct {
		gets  int
		has   []int
		wants []int
	}{
		"should do nothing when the provided value is not in the set": {
			gets:  4,
			has:   []int{1, 2, 3},
			wants: []int{1, 2, 3},
		},
		"should remove the provided value from the set": {
			gets:  2,
			has:   []int{1, 2, 3},
			wants: []int{1, 3},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := New[int]()
			s.Add(test.has...)

			s.Remove(test.gets)

			require.Equal(t, len(test.wants), len(s))
			for _, want := range test.wants {
				assert.Contains(t, s, want)
			}
		})
	}
}

func TestSet_ToSlice(t *testing.T) {
	tests := map[string]struct {
		wants []int
	}{
		"should return the set as a slice": {
			wants: []int{1, 2, 3},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			s := New[int]()
			for _, want := range test.wants {
				s.Add(want)
			}

			sl := s.ToSlice()
			assert.Equal(t, len(test.wants), len(sl))
			for _, want := range test.wants {
				assert.Contains(t, sl, want)
			}
		})
	}
}
