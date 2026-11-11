package utils

import (
	"errors"
	"iter"

	"github.com/hashicorp/go-multierror"

	"github.com/github/token-scanning-service/ts/common"
)

// This is like [slices.Chunk], except that the chunks can overlap.
func ChunkOverlap[Slice ~[]E, E any](s Slice, n, overlap int) iter.Seq[Slice] {
	if n <= 0 {
		panic("n must be positive")
	}
	if overlap < 0 {
		panic("overlap must be greater than or equal to 0")
	}
	if overlap >= n {
		panic("overlap must be less than n")
	}

	return func(yield func(Slice) bool) {
		for start := 0; start < len(s); start += n - overlap {
			end := min(start+n, len(s))

			// Set the capacity of each chunk so that appending to a chunk does
			// not modify the original slice.
			if !yield(s[start:end:end]) {
				return
			}
			if end == len(s) {
				break
			}
		}
	}
}

// Chunking function that stops if error is encountered in any chunk.
//
// Deprecated: Use slice.Chunk.
func ChunkSliceFunc(totalSize, pageSize int, cb func(int, int) error) error {
	if pageSize <= 0 {
		return errors.New("pageSize must be positive")
	}
	for start := 0; start < totalSize; start += pageSize {
		end := min(start+pageSize, totalSize)
		if err := cb(start, end); err != nil {
			return err
		}
	}
	return nil
}

// Chunking function that aggregates errors and does not stop if error is encountered in any chunk.
//
// Deprecated: Use [slices.Chunk].
func ChunkSliceFuncMultierror(totalSize, pageSize, acceptableErrorCount int, cb func(int, int) error) error {
	var multiErr *multierror.Error
	for start := 0; start < totalSize; start += pageSize {
		end := start + pageSize
		if end > totalSize {
			end = totalSize
		}
		if err := cb(start, end); err != nil {
			multiErr = multierror.Append(multiErr, err)

			if len(multiErr.WrappedErrors()) > acceptableErrorCount {
				return multiErr.ErrorOrNil()
			}
		}
	}

	return multiErr.ErrorOrNil()
}

func HasIntersection[E comparable](a, b []E) bool {
	if len(a) == 0 || len(b) == 0 {
		return false
	}
	set := make(common.Set[E])
	for _, item := range a {
		set.Add(item)
	}
	for _, v := range b {
		if set.Has(v) {
			return true
		}
	}
	return false
}

func ToAnySlice[Slice ~[]E, E any](s Slice) ([]any, error) {
	out := make([]any, len(s))
	for i := 0; i < len(out); i++ {
		out[i] = s[i]
	}
	return out, nil
}
