package interfaces

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/github-telemetry-go/kvp"
)

type AncestorRelationship int

const (
	AncestorRelationshipUnknown AncestorRelationship = iota
	AncestorRelationshipParent
	AncestorRelationshipAncestor
)

type RootAncestor struct {
	PackageName          string               `json:"package_name"`
	Requirements         string               `json:"requirements"`
	AncestorRelationship AncestorRelationship `json:"ancestor_relationship"`
}

type descendantsCache map[*DependencyNode]map[*DependencyNode]struct{}

func (dc descendantsCache) listDescendants(ctx context.Context, manifest *Manifest, seen map[*DependencyNode]struct{}, dep *DependencyNode) (map[*DependencyNode]struct{}, error) {
	if descendants, ok := dc[dep]; ok {
		return descendants, nil
	}

	// check for context cancellation
	// this allows us to time out in the middle
	// of GetRootAncestors
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	descendants := map[*DependencyNode]struct{}{}
	stack := []*DependencyNode{dep}

	for len(stack) > 0 {
		currentDep := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		if _, ok := seen[currentDep]; ok {
			continue
		}
		seen[currentDep] = struct{}{}

		if newDescendants, ok := dc[currentDep]; ok {
			for descendant := range newDescendants {
				descendants[descendant] = struct{}{}
			}
			continue
		}

		for _, depKey := range currentDep.Dependencies {
			subDep, ok := manifest.Resolved[depKey]
			if !ok {
				continue
			}

			descendants[subDep] = struct{}{}
			stack = append(stack, subDep)
		}
	}

	dc[dep] = descendants
	return descendants, nil
}

func listChildren(manifest *Manifest, dep *DependencyNode) map[*DependencyNode]struct{} {
	children := map[*DependencyNode]struct{}{}

	for _, depKey := range dep.Dependencies {
		child, ok := manifest.Resolved[depKey]
		if !ok {
			continue
		}
		children[child] = struct{}{}
	}

	return children
}

type RootAncestorSet map[RootAncestor]struct{}
type RootAncestorMap map[*DependencyNode]RootAncestorSet

func (am RootAncestorMap) addRelation(dep *DependencyNode, rel RootAncestor) {
	if am[dep] == nil {
		am[dep] = RootAncestorSet{}
	}
	am[dep][rel] = struct{}{}
}

func asParent(dep *DependencyNode) RootAncestor {
	return RootAncestor{
		PackageName:          dep.PackageName(),
		Requirements:         dep.Requirements(),
		AncestorRelationship: AncestorRelationshipParent,
	}
}

func asAncestor(anc RootAncestor) RootAncestor {
	anc.AncestorRelationship = AncestorRelationshipAncestor
	return anc
}

// See manifestStats.complexity() for how this is calculated.
// This number was chosen by looking at data over 24 hours.
// Above this threshold we basically never return results in
// under 5 seconds.
const MAXIMUM_MANIFEST_COMPLEXITY = 200_000_000

func GetRootAncestors(ctx context.Context, repoID uint64, manifest *Manifest) (RootAncestorMap, error) {
	am := RootAncestorMap{}
	if err := ctx.Err(); err != nil {
		return am, err
	}
	manifestStats := getManifestStats(manifest)
	loggerFields := []kvp.Field{
		kvp.Uint64("gh.repo.id", repoID),
		kvp.Uint64("snapshot.id", manifest.SnapshotID),
		kvp.Int("dependencies.count", manifestStats.totalDependencies),
		kvp.Int("dependencies.count.direct", manifestStats.directDependencies),
		kvp.Int("dependencies.count.edges", manifestStats.edges),
		kvp.Int("manifest.complexity", manifestStats.complexity()),
		kvp.Int("optimization.version", 1),
	}
	if manifestStats.shouldSkip() {
		contextlogger.Warn(ctx, "GetRootAncestors skipping manifest due to high complexity", loggerFields...)
		return am, nil
	}
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "GetRootAncestors", "GetRootAncestors", loggerFields...)
	defer ender()
	dc := descendantsCache{}
	for _, dep := range manifest.Resolved {
		if dep.Relationship == Direct { // transitive dependencies will be found while traversing
			parent := dep
			children := listChildren(manifest, dep)
			if len(children) == 0 {
				continue
			}
			parentAnc := asParent(parent)
			ancestorAnc := asAncestor(parentAnc)
			for child := range children {
				am.addRelation(child, parentAnc)

				descendants, err := dc.listDescendants(ctx, manifest, map[*DependencyNode]struct{}{}, child)
				if err != nil {
					return nil, err
				}
				for descendant := range descendants {
					am.addRelation(descendant, ancestorAnc)
				}
			}
		}
	}

	return am, nil
}

type manifestStats struct {
	totalDependencies  int
	directDependencies int
	edges              int
}

func (ms *manifestStats) complexity() int {
	// We do a BFS from each direct dependency to find all its descendants.
	// This should run in O(D(N + E)):
	//  - D is the number of direct dependencies
	//  - N is the number of nodes in the graph
	//  - E is the number of edges in the graph
	return ms.directDependencies * (ms.totalDependencies + ms.edges)
}

// shouldSkip() returns true if there's basically zero chance of returning
// in under 5 seconds. Returning false is not a guarantee that we will
// complete in time, it just means there's a chance.
func (ms *manifestStats) shouldSkip() bool {
	return ms.complexity() > MAXIMUM_MANIFEST_COMPLEXITY
}

func getManifestStats(manifest *Manifest) manifestStats {
	stats := manifestStats{
		totalDependencies: len(manifest.Resolved),
	}
	for _, dep := range manifest.Resolved {
		if dep.Relationship == Direct {
			stats.directDependencies++
		}
		stats.edges += len(dep.Dependencies)
	}
	return stats
}
