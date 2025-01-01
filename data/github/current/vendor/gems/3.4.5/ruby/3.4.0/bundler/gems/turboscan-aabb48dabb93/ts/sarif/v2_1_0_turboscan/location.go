package v210turboscan

import (
	"github.com/github/turboscan/ts/transforms"
)

func (l *Location) setPhysicalLocation(artLocations map[int]*ArtifactLocation) {
	if l.PhysicalLocation == nil {
		return
	}
	if l.PhysicalLocation.ArtifactLocation == nil {
		return
	}
	artLoc := l.PhysicalLocation.ArtifactLocation
	// if artifactLocation already has the Uri or UriBaseId then stop the lookup
	if artLoc.Uri != "" {
		return
	}
	if artLoc.UriBaseId != "" {
		return
	}
	loc, ok := artLocations[artLoc.Index]
	if !ok {
		return
	}
	l.PhysicalLocation.ArtifactLocation = loc
}

func (r *Run) allArtifactLocations() map[int]*ArtifactLocation {
	locations := transforms.Map(r.Artifacts, func(a *Artifact) *ArtifactLocation {
		if a == nil {
			return &ArtifactLocation{Index: -1}
		}
		if a.Location == nil {
			return &ArtifactLocation{Index: -1}
		}
		return a.Location
	})
	// The following is guaranteed to result in the correct behaviour based on
	// the SARIF spec §3.4.5 index property.
	// If thisObject occurs as the location property (§3.24.2) of an artifact
	// object in theRun.artifacts, then index MAY be present. If present,
	// it SHALL equal the array index within theRun.artifacts of the containing
	// artifact object.
	for i, loc := range locations {
		loc.Index = i
	}
	return transforms.IndexBy(locations, func(loc *ArtifactLocation) int { return loc.Index })
}

func (r *Run) normaliseLocations() {
	locations := r.allArtifactLocations()
	for _, res := range r.Results {
		for _, loc := range res.Locations {
			loc.setPhysicalLocation(locations)
		}
	}
}

func (r *Run) normaliseRelatedLocations() {
	locations := r.allArtifactLocations()
	for _, res := range r.Results {
		if len(res.RelatedLocations) == 0 {
			continue
		}
		for _, relLoc := range res.RelatedLocations {
			relLoc.setPhysicalLocation(locations)
		}
	}
}
