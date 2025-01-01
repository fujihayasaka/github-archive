package upgrades

import (
	"fmt"
	"path/filepath"
	"runtime"
)

// VersionFromFile returns the transition version from a filename or zero if the filename does not look like a
// transition. Files should match the pattern <integer>_<string>.go.
func VersionFromFile(path string) (uint, bool) {
	base := filepath.Base(path)

	var version uint
	var name string

	matches, _ := fmt.Sscanf(base, "%d_%s.go", &version, &name)

	return version, matches == 2
}

func mustGetVersion() uint {
	for i := 1; ; i++ {
		_, file, _, ok := runtime.Caller(i)
		if !ok {
			panic("could not get filename of caller")
		}

		if schemaVersion, ok := VersionFromFile(file); ok {
			return schemaVersion
		}
	}
}
