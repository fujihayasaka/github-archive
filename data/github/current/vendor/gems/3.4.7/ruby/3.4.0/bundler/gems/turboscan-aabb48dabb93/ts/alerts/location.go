package alerts

import "github.com/github/turboscan/ts"

// Location corresponds to a location in source code represented with a linehash
type Location struct {
	// Character-based Karp-Rabin hash, ignoring whitespace apart from newlines, but normalising newlines
	// 100 character window
	// Format: <long hash>:<disambiguating ordinal>
	Fingerprint string
	FilePath    string
	Region      ts.Region
	Snippet     *ts.Snippet
}

// Length returns the length of the location which is the end column minus the start column
func (loc Location) Length() uint32 {
	return loc.Region.EndColumn - loc.Region.StartColumn
}

// Column returns the start column
func (loc Location) Column() uint32 {
	return loc.Region.StartColumn
}
