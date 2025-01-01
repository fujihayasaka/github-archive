package v210autofix

func (r *Result) FindRelatedLocation(targetId int) *Location {
	for _, location := range r.RelatedLocations {
		if location.Id == targetId {
			return location
		}
	}
	return nil
}
