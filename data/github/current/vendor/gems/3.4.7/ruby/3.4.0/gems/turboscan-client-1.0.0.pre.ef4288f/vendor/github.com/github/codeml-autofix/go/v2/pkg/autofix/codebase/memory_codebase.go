package codebase

import (
	"net/url"
	"path/filepath"
	"reflect"
	"strings"

	"github.com/bmatcuk/doublestar"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/pkg/errors"
)

// MemoryCodebase is an implementation of VirtualCodebase that stores files in memory
type MemoryCodebase struct {
	// Root is a virtual root path (like "/")
	Root string
	// Files is a map from file path to file content
	Files map[string]string
}

// NewMemoryCodebase creates a new MemoryCodebase with the given files
// This version accepts a map of string paths to byte[] contents.
// This function is equivalent to NewMemoryCodebaseStrings, but allows for byte slices
func NewMemoryCodebase(files map[string][]byte) *MemoryCodebase {
	stringFiles := make(map[string]string, len(files))
	for path, content := range files {
		stringFiles[path] = string(content)
	}
	return &MemoryCodebase{
		Root:  "/",
		Files: stringFiles,
	}
}

// NewMemoryCodebaseStrings creates a new MemoryCodebase with the given files
// This version accepts a map of string paths to string contents.
// This function is equivalent to NewMemoryCodebase, but allows for string slices
func NewMemoryCodebaseStrings(stringFiles map[string]string) *MemoryCodebase {
	return &MemoryCodebase{
		Root:  string(filepath.Separator),
		Files: stringFiles,
	}
}

// GetRoot returns the root path of the codebase
func (mc *MemoryCodebase) GetRoot() string {
	return mc.Root
}

// ReadContents reads the contents of a file in the codebase
func (mc *MemoryCodebase) ReadContents(path string) (string, error) {
	content, ok := mc.Files[path]
	if !ok {
		return "", errors.Errorf("file not found: %s", path)
	}
	return content, nil
}

// WriteContents writes content to a file in the codebase
func (mc *MemoryCodebase) WriteContents(path string, contents string) error {
	mc.Files[path] = contents
	return nil
}

// FindFiles finds all files matching the given globs
func (mc *MemoryCodebase) FindFiles(globs []string) ([]string, error) {
	// This is a simplified implementation that doesn't handle all glob patterns
	var results []string

	for path := range mc.Files {
		for _, glob := range globs {
			matched, err := doublestar.PathMatch(glob, path)
			if err != nil {
				return nil, err
			}
			if matched {
				results = append(results, path)
				break
			}
		}
	}

	return results, nil
}

// Equals checks if this codebase equals another
func (mc *MemoryCodebase) Equals(that VirtualCodebase) bool {
	other, ok := that.(*MemoryCodebase)
	if !ok {
		return false
	}

	if len(mc.Files) != len(other.Files) {
		return false
	}

	for path, content := range mc.Files {
		otherContent, ok := other.Files[path]
		if !ok || content != otherContent {
			return false
		}
	}

	return true
}

// GetFile gets a file by its URI
func (mc *MemoryCodebase) GetFile(uri string) (File, error) {
	var path string

	if strings.HasPrefix(uri, "file:") {
		parsedURL, err := url.Parse(uri)
		if err != nil {
			return File{}, st.EnsureStackTrace(err, "invalid file URI")
		}

		path = parsedURL.Path
	} else {
		path = uri
	}

	path = filepath.Clean(path)

	if _, ok := mc.Files[path]; !ok {
		if strings.HasPrefix(uri, "file:") {
			return File{}, errors.Errorf("file not found: %s (from URI: %s)", path, uri)
		}
		return File{}, errors.Errorf("file not found: %s", path)
	}

	return File{Codebase: mc, Path: path}, nil
}

// Read reads a region of a file
func (mc *MemoryCodebase) Read(path string, region RegionReader) (string, error) {
	content, err := mc.ReadContents(path)
	if err != nil {
		return "", err
	}

	if region == nil {
		return content, nil
	}

	return region.read(content), nil
}

// Hash returns a hash for this codebase
// For memory codebases, we don't distinguish between different instances.
// Rather, the files themselves generate the hash.
func (mc *MemoryCodebase) Hash() string {
	return reflect.TypeOf(mc).String() + ":memory"
}

// NewMockFile creates a mock file with the given name and contents from a single-file mock
// codebase.
func NewMockFile(name string, contents string) File {
	cb := NewMemoryCodebaseStrings(map[string]string{name: contents})

	file, err := cb.GetFile(name)
	if err != nil {
		panic(err)
	}
	return file
}

// Ensure MemoryCodebase implements VirtualCodebase
var _ VirtualCodebase = (*MemoryCodebase)(nil)
