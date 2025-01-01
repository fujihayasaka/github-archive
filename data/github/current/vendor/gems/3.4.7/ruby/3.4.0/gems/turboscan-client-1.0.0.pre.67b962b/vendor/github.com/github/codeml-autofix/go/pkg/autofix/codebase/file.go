package codebase

// File provides utilities for handling code files and their contents.
import "strings"

// File represents a file within a codebase, providing methods to read and manipulate its contents.
// It works with both line-based (LineRegion) and column-based (Region) selections.
//
// Usage:
//
//	file := File{Codebase: someCodebase, Path: "path/to/file"}
//	content, err := file.Read(LineRegion{...})
type File struct {
	// codebase is the codebase containing the file.
	Codebase VirtualCodebase
	// path is the path to the file within the codebase.
	Path string
}

// Read reads a region of characters from a file in this codebase.
// Returns the content as string and any error encountered during reading.
func (f File) Read(region LineRegion) (string, error) {
	contents, err := f.ReadContents()
	if err != nil {
		return "", err
	}
	return ReadLineRegion(contents, region), nil
}

// ReadWithColumns reads a region with column-specific boundaries.
// Useful for precise selections within lines (e.g., function parameters).
func (f File) ReadWithColumns(region Region) (string, error) {
	contents, err := f.ReadContents()
	if err != nil {
		return "", err
	}
	return ReadFullRegion(contents, region), nil
}

// ReadContents reads the entire file content.
// Delegates to the underlying codebase implementation.
func (f File) ReadContents() (string, error) {
	return f.Codebase.ReadContents(f.Path)
}

// WriteContents writes the contents of a file.
func (f File) WriteContents(contents string) error {
	return f.Codebase.WriteContents(f.Path, contents)
}

func (f File) Hash() string {
	return f.Codebase.Hash() + ":" + f.Path
}

// GetNumberOfLines returns the count of newline-separated lines in the file.
// Returns 0 for empty files.
func (f File) GetNumberOfLines() (int, error) {
	content, err := f.ReadContents()
	if err != nil {
		return 0, err
	}
	if len(content) == 0 {
		return 0, nil
	}
	// Count the number of newline characters
	return len(strings.Split(content, "\n")), nil
}

// Equals checks if two files are identical by comparing their codebase and path.
// Two files are equal if they point to the same path in the same codebase.
func (f File) Equals(that File) bool {
	return f.Codebase.Equals(that.Codebase) && f.Path == that.Path
}
