package codebase

import (
	"crypto/sha256"
	"errors"
	"path/filepath"
	"reflect"
	"slices"

	"github.com/github/codeml-autofix/go/pkg/autofix/utils"
)

type MockCodeBase struct {
	files map[string]string
}

var _ VirtualCodebase = &MockCodeBase{} // nolint:exhaustruct

func (MockCodeBase) GetRoot() string {
	return "mock"
}

func (c MockCodeBase) ReadContents(pth string) (string, error) {
	contents, found := c.files[pth]
	if !found {
		return "", errors.New("Unable to read " + pth + " from mock codebase.")
	} else {
		return contents, nil
	}
}

func (MockCodeBase) WriteContents(pth, contents string) error {
	return errors.New("WriteContents is not implemented for MockCodeBase")
}

// FindFiles finds all files in the codebase that match the given globs.
func (c MockCodeBase) FindFiles(globs []string) ([]string, error) {
	matches := []string{}
	for path := range c.files {
		for _, pattern := range globs {
			normalizedPath := "./" + path
			matched, _ := filepath.Match(pattern, path)
			normalizedMatch, _ := filepath.Match(pattern, normalizedPath)
			eitherMatched := matched || normalizedMatch
			// We check if the pattern matches either the original path or the normalized path.
			// If it does, we add the path to the matches.
			if eitherMatched {
				matches = append(matches, path)
			}
		}
	}
	if len(matches) == 0 {
		return nil, errors.New("no files found matching the given patterns")
	}
	return matches, nil
}

func (c MockCodeBase) Equals(that VirtualCodebase) bool {
	return reflect.DeepEqual(c, that)
}

func (c MockCodeBase) GetFile(path string) (File, error) {
	_, found := c.files[path]
	if !found {
		return File{}, errors.New("Unable to read " + path + " from mock codebase.")
	}
	return File{
		Codebase: c,
		Path:     path,
	}, nil
}

func (MockCodeBase) Read(path string, region RegionReader) (string, error) {
	return "", errors.New("Read is not implemented for MockCodeBase")
}

func (m MockCodeBase) Hash() string {
	// compute the sha256 hash of the files (paths and contents) in the codebase
	hash := sha256.New()
	paths := utils.Keys(m.files)
	slices.Sort(paths)
	for _, path := range paths {
		hash.Write([]byte(path))
		contents := m.files[path]
		hash.Write([]byte(contents))
	}
	return string(hash.Sum(nil))
}

func (MockCodeBase) ReadLines(path string, startLine LineNumber, endLine LineNumber) ([]string, error) {
	return nil, errors.New("ReadLines is not implemented for MockCodeBase")
}

func NewMockCodeBase(files map[string]string) *MockCodeBase {
	return &MockCodeBase{
		files: files,
	}
}

// Create a mock file with the given name and contents from a single-file mock
// codebase.
func NewMockFile(name string, contents string) File {
	cb := NewMockCodeBase(map[string]string{name: contents})

	file, err := cb.GetFile(name)
	if err != nil {
		panic(err)
	}
	return file
}
