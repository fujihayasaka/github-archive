package common

type Set[T comparable] map[T]struct{} // I can't believe the stdlib doesn't include this

func NewSetWithCapacity[T comparable](cap int) Set[T] {
	return make(map[T]struct{}, cap)
}

func NewSet[T comparable](values []T) Set[T] {
	var m map[T]struct{}
	if len(values) > 0 {
		m = make(map[T]struct{}, len(values))
	} else {
		m = make(map[T]struct{})
	}
	for _, v := range values {
		m[v] = struct{}{}
	}
	return m
}

func (s Set[T]) Has(value T) bool {
	_, ok := s[value]
	return ok
}

func (s Set[T]) Add(values ...T) {
	for _, value := range values {
		if !s.Has(value) {
			s[value] = struct{}{}
		}
	}
}

func (s Set[T]) Merge(incoming Set[T]) {
	for k := range incoming {
		s.Add(k)
	}
}

func (s Set[T]) Keys() []T {
	keys := make([]T, 0, len(s))
	for k := range s {
		keys = append(keys, k)
	}
	return keys
}

func (s Set[T]) Remove(value T) {
	delete(s, value)
}

func (s Set[T]) Clear() {
	clear(s)
}

// IsSubsetOf returns true if s is a subset of other.
func (s Set[T]) IsSubsetOf(other Set[T]) bool {
	if len(s) > len(other) {
		return false
	}
	for k := range s {
		if !other.Has(k) {
			return false
		}
	}
	return true
}

func (s Set[T]) Equals(other Set[T]) bool {
	if len(s) != len(other) {
		return false
	}
	return s.IsSubsetOf(other)
}
