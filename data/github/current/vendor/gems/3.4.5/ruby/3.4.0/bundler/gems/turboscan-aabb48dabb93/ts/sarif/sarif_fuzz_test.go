package sarif_test

import (
	"testing"

	"github.com/github/turboscan/ts/sarif"
)

func FuzzEscape(f *testing.F) {
	// This runs against the following cases normally. To run a full fuzz test use the command:
	// go test -fuzz=FuzzEscape ./ts/sarif/fuzz_test.go
	testcases := []string{"Hello, world", "", "!12345", "%25f", "%20", "%00", "abc/def%2Fhello.js", "//0", ":", "%3B", "$"}
	for _, tc := range testcases {
		f.Add(tc) // Use f.Add to provide a seed corpus
	}

	f.Fuzz(func(t *testing.T, orig string) {
		// Parse the incoming url
		storedInDB, err := sarif.URIToPath(orig, "")
		if err != nil {
			t.Skip()
			return
		}
		// The stored value is serialized again
		toNewSARIF := sarif.BuildArtifactLocation(storedInDB).Uri
		// We try to parse again - this should match the DB value so that we do not change it after a serialization/parse cycle
		newSARIFParsed, err := sarif.URIToPath(toNewSARIF, "")
		if err != nil {
			t.Errorf("Failed after: %q (%q), after: %q (%q) %q", storedInDB, orig, newSARIFParsed, toNewSARIF, err)
			return
		}
		if newSARIFParsed != storedInDB {
			t.Errorf("Before: %q (%q), after: %q (%q)", storedInDB, orig, newSARIFParsed, toNewSARIF)
			return
		}
	})
}
