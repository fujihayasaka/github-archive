package v210autofix

// Equals compares two Artifact values.
func (a Artifact) Equals(that Artifact) bool {
	return a.Location.Uri == that.Location.Uri && a.Contents.Text == that.Contents.Text
}
