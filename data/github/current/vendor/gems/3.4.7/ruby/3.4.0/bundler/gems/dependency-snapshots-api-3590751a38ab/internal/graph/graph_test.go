package graph

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGraphSimple(t *testing.T) {
	g := newGraph()
	g.AddEdge("child2", "child1")
	g.AddEdge("child3", "child1")
	g.AddEdge("child4", "child3")
	g.AddEdge("child1", "parent")

	path, err := g.FindPaths("child2", map[string]struct{}{"parent": {}})
	require.NoError(t, err, "error resolving: child2 -> parent")
	require.Len(t, path, 1)
	checkPath(t, "child2 -> parent", []string{"child1", "parent"}, path[0])

	path, err = g.FindPaths("child3", map[string]struct{}{"parent": {}})
	require.NoError(t, err, "error resolving: child3 -> parent")
	require.Len(t, path, 1)
	checkPath(t, "child3 -> parent", []string{"child1", "parent"}, path[0])

	path, err = g.FindPaths("child4", map[string]struct{}{"parent": {}})
	require.NoError(t, err, "error resolving: child4 -> parent")
	require.Len(t, path, 1)
	checkPath(t, "child4 -> parent", []string{"child3", "child1", "parent"}, path[0])
}

func TestGraphDiamondPaths(t *testing.T) {
	g := newGraph()
	g.AddEdge("Root", "D")
	g.AddEdge("Root", "Z")
	g.AddEdge("D", "C")
	g.AddEdge("Z", "Y")
	g.AddEdge("C", "B")
	g.AddEdge("Y", "X")
	g.AddEdge("X", "Leaf")
	g.AddEdge("B", "Leaf")

	expected := []Path{
		{"Z", "Y", "X", "Leaf"},
		{"D", "C", "B", "Leaf"},
	}

	paths, err := g.FindPaths("Root", map[string]struct{}{"Leaf": {}})
	require.NoError(t, err, "error resolving: Root -> Leaf")
	require.Len(t, paths, 2)
	checkPaths(t, expected, paths)
}

func TestGraphCyclePaths(t *testing.T) {
	g := newGraph()
	g.AddEdge("Root", "A")
	g.AddEdge("Root", "Z")
	g.AddEdge("A", "B")
	g.AddEdge("B", "C")
	g.AddEdge("C", "A") // cycle
	g.AddEdge("Z", "Y")
	g.AddEdge("Y", "X")
	g.AddEdge("X", "Leaf")

	expected := []Path{
		{"Z", "Y", "X", "Leaf"},
	}

	paths, err := g.FindPaths("Root", map[string]struct{}{"Leaf": {}})
	require.NoError(t, err, "error resolving: Root -> Leaf")
	require.Len(t, paths, 1)
	checkPaths(t, expected, paths)
}

func TestGraphCyclePathsFromRoot(t *testing.T) {
	g := newGraph()
	g.AddEdge("Root", "A")
	g.AddEdge("Root", "Z")
	g.AddEdge("A", "B")
	g.AddEdge("B", "C")
	g.AddEdge("B", "D")
	g.AddEdge("D", "Leaf")
	g.AddEdge("C", "A") // cycle
	g.AddEdge("Z", "Y")
	g.AddEdge("Y", "X")
	g.AddEdge("X", "Leaf")

	expected := []Path{
		{"A", "B", "D", "Leaf"},
		{"Z", "Y", "X", "Leaf"},
	}

	paths, err := g.FindPaths("Root", map[string]struct{}{"Leaf": {}})
	require.NoError(t, err, "error resolving: Root -> Leaf")
	require.Len(t, paths, 2)
	checkPaths(t, expected, paths)
}
