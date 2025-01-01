package interfaces

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
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

func (dc descendantsCache) listDescendants(manifest *Manifest, seen map[*DependencyNode]struct{}, dep *DependencyNode) map[*DependencyNode]struct{} {
	if descendants, ok := dc[dep]; ok {
		return descendants
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
	return descendants
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

func (am RootAncestorMap) addParent(dep *DependencyNode, parent *DependencyNode) {
	if am[dep] == nil {
		am[dep] = RootAncestorSet{}
	}
	anc := RootAncestor{
		PackageName:          parent.PackageName(),
		Requirements:         parent.Requirements(),
		AncestorRelationship: AncestorRelationshipParent,
	}

	am[dep][anc] = struct{}{}
}

func (am RootAncestorMap) addAncestor(dep *DependencyNode, ancestor *DependencyNode) {
	if am[dep] == nil {
		am[dep] = RootAncestorSet{}
	}
	anc := RootAncestor{
		PackageName:          ancestor.PackageName(),
		Requirements:         ancestor.Requirements(),
		AncestorRelationship: AncestorRelationshipAncestor,
	}

	am[dep][anc] = struct{}{}
}

func GetRootAncestors(ctx context.Context, manifest *Manifest) RootAncestorMap {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "GetRootAncestors", "GetRootAncestors")
	defer ender()
	am := RootAncestorMap{}
	dc := descendantsCache{}
	for _, dep := range manifest.Resolved {
		if dep.Relationship == Direct { // transitive dependencies will be found while traversing
			parent := dep
			children := listChildren(manifest, dep)
			for child := range children {
				am.addParent(child, parent)

				descendants := dc.listDescendants(manifest, map[*DependencyNode]struct{}{}, child)
				for descendant := range descendants {
					am.addAncestor(descendant, parent)
				}
			}
		}
	}

	return am
}
