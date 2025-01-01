package ts

// Region defines a contiguous portion of an artifact
//
// Note: The region type does not have an ID because it is embedded on
// the database side.
type Region struct {
	// Start of location on the line
	StartColumn uint32
	// End of location (note this may be beyond the line)
	EndColumn uint32

	StartLine uint32
	EndLine   uint32
}

func (region Region) IsWholeFile() bool {
	return region.StartLine == 0 && region.EndLine == 0 && region.StartColumn == 0 && region.EndColumn == 0
}
