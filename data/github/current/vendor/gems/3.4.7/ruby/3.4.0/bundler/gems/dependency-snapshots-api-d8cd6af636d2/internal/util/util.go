// util contains mostly generic functions/types that are used by multiple other packages in this project.
// Hopefully many or all of these will eventually be added to the Go standard library in some form,
// or at the very least a well-regarded library that we can end up bringing in.
package util

import (
	"fmt"
	"time"

	otelkvp "github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-kvp"
	"go.uber.org/zap"
	"golang.org/x/exp/maps"
	"golang.org/x/exp/utf8string"
)

type Set[T comparable] struct {
	// linting with generics is still a bit of a pain
	m map[T]struct{} //nolint:structcheck
}

func NewSet[T comparable]() Set[T] {
	return Set[T]{m: make(map[T]struct{})}
}

func ToSet[T comparable](items []T) Set[T] {
	m := make(map[T]struct{})
	for _, item := range items {
		m[item] = struct{}{}
	}
	return Set[T]{m: m}
}

func (s Set[T]) Add(item T) {
	if s.m == nil {
		s.m = make(map[T]struct{})
	}
	s.m[item] = struct{}{}
}

func (s Set[T]) Contains(item T) bool {
	_, ok := s.m[item]
	return ok
}

func (s Set[T]) Values() []T {
	return maps.Keys(s.m)
}

func (s Set[T]) AddAll(s2 Set[T]) {
	for _, item := range s2.Values() {
		s.Add(item)
	}
}

func (s Set[T]) Union(s2 Set[T]) Set[T] {
	ret := NewSet[T]()
	ret.AddAll(s)
	ret.AddAll(s2)
	return ret
}

func Map[A, B any](slice []A, f func(A) B) []B {
	ret := make([]B, 0, len(slice))
	for _, item := range slice {
		ret = append(ret, f(item))
	}
	return ret
}

func Retry[A any](maxTries int, baseDelay time.Duration, f func() (result A, retryable bool, err error)) (A, error) {
	var err error
	for tries := 0; tries < maxTries; tries++ {
		ret, retryable, err := f()
		if err != nil {
			if !retryable {
				return ret, err
			}
			// turning tries+1 into a Duration is weird, but it's necessary in order to do the math here
			time.Sleep(baseDelay * time.Duration(tries+1))
		} else {
			return ret, nil
		}
	}
	return *new(A), err
}
func ToOtelKVP(fields ...kvp.Field) []otelkvp.Field {
	o := make([]otelkvp.Field, 0, len(fields))
	for _, f := range fields {
		var of otelkvp.Field
		switch f.T {
		case kvp.AnyType:
			of = otelkvp.Any(f.Key, f.Any)
		case kvp.BoolType:
			of = otelkvp.Bool(f.Key, f.Boolean)
		case kvp.IntType:
			of = otelkvp.Int(f.Key, int(f.Int))
		case kvp.UintType:
			of = otelkvp.Uint(f.Key, uint(f.Int))
		case kvp.FloatType:
			of = otelkvp.Float64(f.Key, f.AsFloat())
		case kvp.DurationType:
			of = otelkvp.Duration(f.Key, f.AsDuration())
		case kvp.TimeType:
			of = otelkvp.Time(f.Key, f.AsTime())
		case kvp.StringType:
			of = otelkvp.String(f.Key, f.Str)
		case kvp.LazyType:
			// no longer lazy, but we never use it.
			of = otelkvp.Any(f.Key, f.LazyValue())
		case kvp.ErrorType:
			err, ok := f.Any.(error)
			if ok {
				of = zap.NamedError(f.Key, err)
			} else {
				// Looking at the kvp library, they store the error
				// as a string in Str and the error inside "Any". Therefore
				// this branch should never happen, but is here to avoid
				// panics in case the old library makes a breaking change.
				of = otelkvp.String(f.Key, f.Str)
			}
		}
		o = append(o, of)
	}
	return o
}

// truncate cuts a utf8 string down to a given number of codepoints.
func Truncate(s string, length int) string {
	us := utf8string.NewString(s)
	if us.RuneCount() < length {
		return s
	} else {
		return fmt.Sprintf("%s...", us.Slice(0, length))
	}
}
