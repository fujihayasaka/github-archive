// Package set contains a generic set implementation.
package set

// Set is a generic set data structure that uses a map for storage.
// Tye type parameter E must be comparable.
type Set[E comparable] map[E]struct{}

// FromSlice creates and returns a new Set from a slice of values.
func FromSlice[E comparable](sl []E) Set[E] {
	s := Set[E]{}
	for _, v := range sl {
		s.Add(v)
	}
	return s
}

// New creates and returns a new Set. It accepts a variadic number of values to
// initialize the set with.
func New[E comparable](vs ...E) Set[E] {
	s := make(Set[E])
	for _, v := range vs {
		s.Add(v)
	}
	return s
}

// Add inserts values into the set.
func (s Set[E]) Add(vs ...E) {
	for _, v := range vs {
		s[v] = struct{}{}
	}
}

// Contains checks if a value is present in the set.
// Returns true if the value is found, false otherwise.
func (s Set[E]) Contains(v E) bool {
	_, ok := s[v]
	return ok
}

// Remove deletes a value from the set.
func (s Set[E]) Remove(v E) {
	delete(s, v)
}

// ToSlice converts the set to a slice of values.
// Returns a slice containing all the values in the set.
func (s Set[E]) ToSlice() []E {
	sl := make([]E, len(s))
	i := 0
	for k := range s {
		sl[i] = k
		i++
	}
	return sl
}
