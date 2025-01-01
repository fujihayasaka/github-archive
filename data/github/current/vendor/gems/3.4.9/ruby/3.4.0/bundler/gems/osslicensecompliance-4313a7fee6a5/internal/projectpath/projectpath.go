// Package projectpath provides the root path of the project.
// Used to get paths to files from different parts of codebase
// For example to load DB migrations in tests and in server
package projectpath

import (
	"path/filepath"
	"runtime"
)

var (
	_, b, _, _ = runtime.Caller(0)

	// Root folder of this project
	Root = filepath.Join(filepath.Dir(b), "..", "..")
)
