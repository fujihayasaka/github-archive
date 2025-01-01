package v210autofix

func (r Run) Equals(that Run) bool {
	if len(r.Artifacts) != len(that.Artifacts) {
		return false
	}
	for i := range r.Artifacts {
		if !r.Artifacts[i].Equals(*that.Artifacts[i]) {
			return false
		}
	}
	return true
}
