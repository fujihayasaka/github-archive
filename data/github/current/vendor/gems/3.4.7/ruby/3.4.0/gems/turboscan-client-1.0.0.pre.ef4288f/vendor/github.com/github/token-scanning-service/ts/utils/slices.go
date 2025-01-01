package utils

import (
	"errors"
	"reflect"

	"github.com/hashicorp/go-multierror"

	"github.com/github/token-scanning-service/ts/common"
)

// Chunking function that stops if error is encountered in any chunk and where chunks may overlap.
func ChunkSliceFuncOverlap(totalSize int, pageSize int, overlapSize int, cb func(int, int) error) error {
	if pageSize <= 0 {
		return errors.New("pageSize must be positive")
	}
	if overlapSize < 0 {
		return errors.New("overlapSize must be greater than or equal to 0")
	}
	if overlapSize >= pageSize {
		return errors.New("overlapSize must be less than pageSize")
	}
	for start := 0; start < totalSize; start += pageSize - overlapSize {
		end := start + pageSize
		if end > totalSize {
			end = totalSize
		}
		if err := cb(start, end); err != nil {
			return err
		}
		if end == totalSize {
			break
		}
	}

	return nil
}

// Chunking function that stops if error is encountered in any chunk
func ChunkSliceFunc(totalSize int, pageSize int, cb func(int, int) error) error {
	return ChunkSliceFuncOverlap(totalSize, pageSize, 0, cb)
}

// Chunking function that aggregates errors and does not stop if error is encountered in any chunk
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

func HasIntersectionUint64(a, b []uint64) bool {
	if len(a) == 0 || len(b) == 0 {
		return false
	}
	set := make(common.Set[uint64])
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

func HasIntersectionString(a, b []string) bool {
	if len(a) == 0 || len(b) == 0 {
		return false
	}
	set := make(common.Set[string])
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

func ToAnySlice(a any) ([]any, error) {
	v := reflect.ValueOf(a)
	if v.Kind() != reflect.Slice {
		return nil, errors.New("unable to convert a non-slice to an any slice")
	}

	out := make([]any, v.Len())
	for i := 0; i < len(out); i++ {
		out[i] = v.Index(i).Interface()
	}
	return out, nil
}
