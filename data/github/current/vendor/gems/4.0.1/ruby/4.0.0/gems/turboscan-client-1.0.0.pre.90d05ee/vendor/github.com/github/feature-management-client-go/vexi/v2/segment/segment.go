// Package segment contains the definition of a segment.
package segment

import "time"

// Segment represents a segment.
type Segment struct {
	// Name is the name of the segment.
	Name string `json:"name"`

	// Actors is the list of actors of the segment.
	Actors map[string]bool `json:"actors"`

	// UpdatedAt is the time when the segment was last updated in milliseconds since epoch.
	UpdatedAt time.Time `json:"updated_at"`

	// OwningService is the service that owns the segment.
	OwningService string `json:"owning_service"`
}

// GetSegmentResponse is the response returned by the GetSegment method.
type GetSegmentResponse struct {
	Name    string
	Segment *Segment
	Error   error
}

// NewSegment returns a new segment.
func NewSegment(name string, actorsMap map[string]bool, areActorsEmbedded bool) *Segment {
	return &Segment{
		Name:   name,
		Actors: actorsMap,
	}
}

// NewSegmentFromActorList returns a new segment from a list of actors.
func NewSegmentFromActorList(name string, actors []string, areActorsEmbedded bool) *Segment {
	return &Segment{
		Name:   name,
		Actors: actorListToMap(actors),
	}
}

// actorListToMap Converts list of actors to a map of actors names to true, for faster lookup.
func actorListToMap(actors []string) map[string]bool {
	actorsMap := make(map[string]bool, len(actors))
	for _, actor := range actors {
		actorsMap[actor] = true
	}

	return actorsMap
}
