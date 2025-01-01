package ts

import (
	"bytes"
	"encoding/json"
	"sort"
	"strings"

	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
)

// FileSet is a simple implementation of Set.
type FileSet map[string]struct{}

func (s FileSet) Contains(file string) bool {
	_, ok := s[file]
	return ok
}

func (s FileSet) Diff(other FileSet) FileSet {
	diff := make(FileSet)
	for file := range s {
		if !other.Contains(file) {
			diff[file] = struct{}{}
		}
	}
	return diff
}

func (s FileSet) Intersection(other FileSet) FileSet {
	if len(s) == 0 {
		return s
	}
	// Find the intersection of the two sets by iterating over the smaller set.
	var small, large FileSet
	if len(s) < len(other) {
		small, large = s, other
	} else {
		small, large = other, s
	}
	intersection := make(FileSet)
	for file := range small {
		if large.Contains(file) {
			intersection[file] = struct{}{}
		}
	}
	return intersection
}

func (s FileSet) Union(other FileSet) FileSet {
	if len(other) == 0 {
		return s
	}
	union := make(FileSet)
	for file := range s {
		union[file] = struct{}{}
	}
	for file := range other {
		union[file] = struct{}{}
	}
	return union
}

func FileSetUnion(sets ...FileSet) FileSet {
	union := make(FileSet)
	for _, set := range sets {
		union = union.Union(set)
	}
	return union
}

func (s *FileSet) UnmarshalJSON(b []byte) error {
	if *s == nil {
		*s = FileSet{}
	}
	out := *s
	ps := make(pathSet)
	err := json.Unmarshal(b, &ps)
	if err != nil {
		return errors.Wrap(err, "could not unmarshal pathSet to FileSet")
	}
	paths := ps.walk()
	for _, path := range paths {
		out[path] = struct{}{}
	}
	return nil
}

func (s FileSet) MarshalJSON() ([]byte, error) {
	root := make(pathSet)
	for file := range s {
		node := root
		splitPath := strings.Split(file, "/")
		for _, comp := range splitPath {
			if node[comp] == nil {
				node[comp] = make(pathSet)
			}
			node = node[comp]
		}
	}
	return json.Marshal(root.optimize())
}

type pathSet map[string]pathSet

// optimize walks the pathset and combines keys if they have no other children
func (ps pathSet) optimize() pathSet {
	if len(ps) == 1 {
		for outerK, outerV := range ps {
			v := outerV.optimize()
			if len(v) == 1 {
				for innerK, innerV := range v {
					return pathSet{outerK + "/" + innerK: innerV}
				}
			}
		}
	}
	out := pathSet{}
	for k, v := range ps {
		out[k] = v.optimize()
	}
	return out
}

func (ps pathSet) MarshalJSON() ([]byte, error) {
	// check to see if the values have no children
	// if so we can represent them with an array
	useArrayOfKeys := true
	for _, v := range ps {
		if len(v) > 0 {
			useArrayOfKeys = false
		}
	}
	if useArrayOfKeys {
		keys := maps.Keys(ps)
		sort.Strings(keys)
		return json.Marshal(keys)
	}
	// the values have children so we need to represent them
	// as an object of objects
	out := make(map[string]json.RawMessage)
	for k, v := range ps {
		data, err := json.Marshal(v)
		if err != nil {
			return nil, err
		}
		out[k] = data
	}
	return json.Marshal(out)
}

func (ps *pathSet) UnmarshalJSON(b []byte) error {
	if *ps == nil {
		*ps = pathSet{}
	}

	out := *ps

	// if we find an array then it is a set of keys
	if bytes.HasPrefix(b, []byte(`[`)) {
		var component []string
		err := json.Unmarshal(b, &component)
		if err != nil {
			return err
		}
		for _, key := range component {
			out[key] = pathSet{}
		}
	} else {
		// otherwise it is a nested pathSet. we can create a
		// temporary type to avoid a stack overflow.
		type pathSetTmp pathSet
		tmp := (pathSetTmp)(out)
		return json.Unmarshal(b, &tmp)
	}
	return nil
}

// walk the pathSet and return the list of files it contains
func (ps pathSet) walk(base ...string) []string {
	if len(ps) == 0 {
		if len(base) == 0 {
			return nil
		}
		return []string{
			strings.Join(base, "/"),
		}
	}
	out := make([]string, 0)
	for k, v := range ps {
		children := v.walk(append(base, k)...)
		out = append(out, children...)
	}
	return out
}
