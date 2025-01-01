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

func (s Set[T]) Add(value T) {
	if !s.Has(value) {
		s[value] = struct{}{}
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

// Intersect computes the intersection of sets.
// If sets is empty, it returns an empty set.
func IntersectSets[T comparable](sets []Set[T]) Set[T] {
	return IntersectMaps[T](sets)
}

func IntersectMaps[T comparable, V any, M ~map[T]V](maps []M) M {
	if len(maps) == 0 {
		return make(M, 0)
	}

	// make a map of the items in the first map, and given them all 'true'
	items := make(map[T]bool, len(maps[0]))
	for s := range maps[0] {
		items[s] = true
	}

	// for each item, if there's a map that doesn't contain it, give it 'false'
	for i := 1; i < len(maps); i++ {
		for s := range items {
			if _, ok := maps[i][s]; !ok {
				items[s] = false
			}
		}
	}

	// make intersection from the items with 'true'
	intersection := make(M, len(items))
	for s, tf := range items {
		if tf {
			var v V
			intersection[s] = v
		}
	}
	return intersection
}
