package graph

import (
	"github.com/pkg/errors"
)

type Graph interface {
	AddVertex(name string)
	AddEdge(src, dest string)
	FindPaths(src string, dests map[string]struct{}) ([]Path, error)
}

type graph struct {
	// map of vertex names to data structures
	vertices map[string]*vertex
}

// cap the recursion depth when we're extracting dependency tree paths
const maxCaptureDepth = 50

// out-edges to neighbors is only state required
type vertex map[string]*vertex

func newGraph() *graph {
	return &graph{
		vertices: map[string]*vertex{},
	}
}

func (g *graph) AddVertex(name string) {
	if _, found := g.vertices[name]; !found {
		g.vertices[name] = &vertex{}
	}
}

func (g *graph) AddEdge(src, dest string) {
	g.AddVertex(src)
	g.AddVertex(dest)
	(*g.vertices[src])[dest] = g.vertices[dest]
}

// alternative impl that can find all paths between two vertices, at a reasonable but higher expense
func (g *graph) FindPaths(src string, dests map[string]struct{}) ([]Path, error) {
	out := []Path{}

	resultPaths, err := g.findPathsDFS(src, dests, 0, Path{})
	if err != nil {
		return out, errors.Wrapf(err, "failed DFS search for all paths from %q to one of: %v", src, dests)
	}
	out = append(out, resultPaths...)

	return out, nil
}

func (g *graph) findPathsDFS(current string, dests map[string]struct{}, distance uint, path Path) ([]Path, error) {
	// if we've hit a cycle on this path before arriving at one of the dests, bail
	if contains(path, current) {
		return []Path{}, nil
	}
	// if a pathological or mis-shaped submission leads to ridiculous path depths, bail
	if distance > maxCaptureDepth {
		return []Path{}, nil
	}

	// don't capture the initial "src" in the original call to findPathsDFS
	if distance > 0 {
		path = append(path, current)
		if _, found := dests[current]; found {
			return []Path{path}, nil
		}
	}

	edges, found := g.vertices[current]
	if !found {
		return nil, errors.Errorf("vertex %q missing from graph", current)
	}

	// explore all the edges of the current vertex
	out := []Path{}
	for edge := range *edges {
		paths, err := g.findPathsDFS(edge, dests, distance+1, path)
		if err != nil {
			return nil, err
		}

		// only capture non-empty paths that terminate in a direct dependency
		for _, path := range paths {
			if len(path) > 0 {
				last := path[len(path)-1]
				if _, found := dests[last]; found {
					out = append(out, path)
				}
			}
		}
	}

	return out, nil
}

func contains(haystack []string, needle string) bool {
	for _, elem := range haystack {
		if elem == needle {
			return true
		}
	}

	return false
}
