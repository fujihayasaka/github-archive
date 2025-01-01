package v210autofix

// FindRelatedLocation returns the related location with the given id or nil if not found.
func (r *Result) FindRelatedLocation(targetID int) *Location {
	for _, location := range r.RelatedLocations {
		if location.Id == targetID {
			return location
		}
	}
	return nil
}
