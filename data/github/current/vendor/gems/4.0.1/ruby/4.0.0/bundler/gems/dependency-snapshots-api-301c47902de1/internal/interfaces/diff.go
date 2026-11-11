// Everything in this file is meant to support the Diff function,
// which takes two arrays of Snapshots and returns an array of Changes.
//
// Here's how this works, at a high level:
//  1. We convert each set of snapshots into an array of DiffableDeps. A DiffableDep
//     is a struct that contains the metadata from the Snapshot, as well as
//     the manifest name, ecosystem, name, version, and package URL. This makes
//     it trivial to combine multiple snapshots into a single set of dependencies
//     for comparison, while preserving all the information we'll need later.
//  2. We convert each array of DiffableDeps into a map of DiffableManifests. This
//     map format makes it more efficient to compare two sets of DiffableDeps. Given
//     a (manifest_name, dependency) pair, we can quickly look up the corresponding
//     DiffableDep in the other set.
//  3. We find removals by iterating over the first set of DiffableDeps and looking
//     for any that are not present in the second set.
//  4. We find additions by iterating over the second set of DiffableDeps and looking
//     for any that are not present in the first set.
//  5. All the removals and additions are combined into a single array of Changes,
//     which is returned.
package interfaces

import (
	"context"
	"fmt"
	"sort"

	packageurl "github.com/package-url/packageurl-go"
)

// Diff returns a list of changes between two sets of snapshots. `base` is considered
// the "old" set of snapshots, and `target` is considered the "new" set of snapshots.
func Diff(base []*Snapshot, target []*Snapshot) ([]Change, error) {
	baseDeps, err := toDiffableDeps(base)
	if err != nil {
		return nil, err
	}

	targetDeps, err := toDiffableDeps(target)
	if err != nil {
		return nil, err
	}

	return diff(baseDeps, targetDeps), nil
}

type ChangeType int

const (
	ADDED ChangeType = iota
	REMOVED
)

func (c ChangeType) String() string {
	switch c {
	case ADDED:
		return "ADDED"
	case REMOVED:
		return "REMOVED"
	default:
		return "UNKNOWN"
	}
}

type Change struct {
	ChangeType   ChangeType
	SnapshotMeta DiffSnapshotMetadata
	Manifest     string
	Ecosystem    string
	Name         string
	Version      string
	PackageURL   string
	Scope        DependencyScope
}

type DiffSnapshotMetadata struct {
	SnapshotID uint64
	Detector   string
	Correlator string
}

type (
	purlKey     string
	DiffableDep struct {
		SnapshotMeta DiffSnapshotMetadata
		// StablePurl is a representation of the PURL that preserves equality between
		// purls that may have minor formatting or ordering differences.
		StablePurl purlKey
		Manifest   string
		PackageURL string
		Ecosystem  string
		Name       string
		Version    string
		Scope      DependencyScope
	}
)

func diff(deps, other []DiffableDep) []Change {
	return toDiffableManifestMap(deps).diff(toDiffableManifestMap(other))
}

func toDiffableDeps(snapshots []*Snapshot) ([]DiffableDep, error) {
	var deps []DiffableDep

	snapshotsByID := make(map[uint64]*Snapshot)
	for _, s := range snapshots {
		snapshotsByID[s.ID] = s
	}
	deduplicatedManifests := CombineManifests(context.Background(), snapshots)

	for _, manifest := range deduplicatedManifests {
		snap, ok := snapshotsByID[manifest.SnapshotID]
		if !ok {
			return nil, fmt.Errorf("snapshot %d not found", manifest.SnapshotID)
		}
		snapshotMeta := DiffSnapshotMetadata{
			SnapshotID: manifest.SnapshotID,
			Detector:   snap.Detector.Name,
			Correlator: snap.Job.Correlator,
		}

		var manifestKey string
		if manifest.File.SourceLocation != "" {
			manifestKey = manifest.File.SourceLocation
		} else {
			manifestKey = manifest.Name
		}

		for _, dep := range manifest.Resolved {
			purl, err := packageurl.FromString(dep.PackageURL)
			if err != nil {
				return nil, err
			}
			deps = append(deps, DiffableDep{
				SnapshotMeta: snapshotMeta,
				Manifest:     manifestKey,
				StablePurl:   toStablePurl(purl),
				PackageURL:   dep.PackageURL,
				Ecosystem:    purl.Type,
				Name:         purl.Name,
				Version:      purl.Version,
				Scope:        dep.Scope,
			})
		}
	}
	return deps, nil
}

// contains returns true if the given DiffableDep is present in the given slice of DiffableDeps.
func contains(deps map[purlKey]DiffableDep, dep DiffableDep) bool {
	if other, ok := deps[dep.StablePurl]; ok {
		if other.Scope == dep.Scope {
			return true
		}
	}
	return false
}

// subtract returns a new slice of DiffableDeps containing all the elements of the first
// slice that are not present in the second slice.
func subtract(deps map[purlKey]DiffableDep, other map[purlKey]DiffableDep) []DiffableDep {
	var result []DiffableDep
	for _, dep := range deps {
		if !contains(other, dep) {
			result = append(result, dep)
		}
	}
	return result
}

// diffableManifestMap is an optimization over []DiffableDep that makes it more efficient
// to find a given dependency in the list. It is a map from manifest name to a map from
// baseDep to a slice of DiffableDeps.
type diffableManifestMap map[string]map[purlKey]DiffableDep

func toDiffableManifestMap(deps []DiffableDep) diffableManifestMap {
	grouped := make(diffableManifestMap)
	for _, dep := range deps {
		if _, ok := grouped[dep.Manifest]; !ok {
			grouped[dep.Manifest] = make(map[purlKey]DiffableDep)
		}
		grouped[dep.Manifest][dep.StablePurl] = dep
	}
	return grouped
}

func (m diffableManifestMap) diff(other diffableManifestMap) []Change {
	var changes []Change

	// find removals by iterating over m's stuff
	for manifestKey, purlToDep := range m {
		if _, ok := other[manifestKey]; ok {
			// if the manifest is present in both, we'll check for removals
			removed := subtract(purlToDep, other[manifestKey])
			for _, dep := range removed {
				changes = append(changes, toChange(dep, REMOVED))
			}
		} else {
			// if the manifest is not present in other, everything in m is removed
			for _, dep := range purlToDep {
				changes = append(changes, toChange(dep, REMOVED))
			}
		}
	}

	// find additions by iterating over other's stuff
	for manifestKey, purlToDep := range other {
		if _, ok := m[manifestKey]; ok {
			// if the manifest is present in both, we'll check for additions
			added := subtract(purlToDep, m[manifestKey])
			for _, dep := range added {
				changes = append(changes, toChange(dep, ADDED))
			}
		} else {
			// if the manifest is not present in m, everything in other is added
			for _, dep := range purlToDep {
				changes = append(changes, toChange(dep, ADDED))
			}
		}
	}
	return changes
}

func toChange(dep DiffableDep, changeType ChangeType) Change {
	return Change{
		ChangeType:   changeType,
		SnapshotMeta: dep.SnapshotMeta,
		Manifest:     dep.Manifest,
		Ecosystem:    dep.Ecosystem,
		Name:         dep.Name,
		Version:      dep.Version,
		PackageURL:   dep.PackageURL,
		Scope:        dep.Scope,
	}
}

func toStablePurl(p packageurl.PackageURL) purlKey {
	// Sort the qualifiers so that the string representation is stable.
	sort.Slice(p.Qualifiers, func(i, j int) bool {
		return p.Qualifiers[i].Key < p.Qualifiers[j].Key
	})

	return purlKey(fmt.Sprintf("pkg:%s/%s@%s?%s#%s", p.Type, p.Name, p.Version, p.Qualifiers.String(), p.Subpath))
}
