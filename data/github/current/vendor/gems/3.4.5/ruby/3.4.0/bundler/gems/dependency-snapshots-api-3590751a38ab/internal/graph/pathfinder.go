package graph

import (
	"github.com/github/dependency-snapshots-api/internal/interfaces"
)

type Pathfinder interface {
	PathsFrom(purl string) ([]Path, error)
}

type Path = []string

type pathfinder struct {
	directs map[string]struct{}
	g       Graph
}

func New(m *interfaces.Manifest) (pathfinder, error) {
	directs := map[string]struct{}{}
	var g Graph = newGraph()

	// populate the data structures to calculate transitive paths
	for dependent, node := range m.Resolved {
		if len(dependent) == 0 {
			continue
		}

		// cache list of dependencies labeled as DependencyRelationship#Direct
		// paths from each package to these packages are what we'll capture
		if node.Relationship == interfaces.Direct {
			directs[dependent] = struct{}{}
		}

		if len(node.Dependencies) == 0 {
			g.AddVertex(dependent)
			continue
		}

		// invert directed edges between dependent and dependencies
		for _, dependency := range node.Dependencies {
			if len(dependency) != 0 {
				g.AddEdge(dependency, dependent)
			}
		}
	}

	return pathfinder{
		directs: directs,
		g:       g,
	}, nil
}

// return an array of Paths, each of which leads from the "target"
// dependency, up to one of it's roots, assumed to be direct
// dependencies. There can be more than one root per target,
// and more than one path from target to each root
func (p pathfinder) PathsFrom(target string) ([]Path, error) {
	// if we didn't find any DependencyRelationship#Direct
	// in the manifest entry, then there's nothing to do here
	if len(p.directs) == 0 {
		return []Path{}, nil
	}

	// find one or more Paths from the target to each root (direct dependency)
	return p.g.FindPaths(target, p.directs)
}
