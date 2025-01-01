package servermigrator

import (
	"iter"
	"testing"

	"github.com/stretchr/testify/assert"
)

func all[T any](a iter.Seq[T]) []T {
	var all []T
	for resource := range a {
		all = append(all, resource)
	}
	return all
}

func Test_batchIter(t *testing.T) {
	type args struct {
		i         iter.Seq[int]
		batchSize int
	}
	type testCase struct {
		name string
		args args
		want [][]int
	}
	tests := []testCase{
		{
			name: "should return an empty slice when the input slice is empty",
			args: args{i: func(yield func(int) bool) {}, batchSize: 1},
			want: nil,
		},
		{
			name: "should return multiple batches when the input slice is larger than the batch size",
			args: args{i: func(yield func(int) bool) {
				for j := range 6 {
					if !yield(j) {
						return
					}
				}
			}, batchSize: 2},
			want: [][]int{{0, 1}, {2, 3}, {4, 5}},
		},
		{
			name: "should return a single batch when the input slice is smaller than the batch size",
			args: args{i: func(yield func(int) bool) {
				for j := range 3 {
					if !yield(j) {
						return
					}
				}
			}, batchSize: 5},
			want: [][]int{{0, 1, 2}},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, all(batchIter(tt.args.i, tt.args.batchSize)), "batchIter(%v, %v)", all(tt.args.i), tt.args.batchSize)
		})
	}
}

func emptyIter[T any]() iter.Seq[T] { return func(yield func(T) bool) {} }
