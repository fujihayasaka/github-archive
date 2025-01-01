package ts

import (
	"crypto/sha256"
	"fmt"

	"github.com/pkg/errors"
)

type SuggestedFixFileID uint64

const (
	FilePathHashSize = sha256.Size
)

type SuggestedFixFilePathHash [FilePathHashSize]byte

type SuggestedFixFile struct {
	BaseModel
	ID             SuggestedFixFileID
	SuggestedFixID SuggestedFixID
	FilePath       string
	FilePathHash   []byte       // 32byte sha256
	FileChecksum   Sha1Checksum // checksum of the file content (20byte)
	DiffContent    []byte
	RepositoryID   RepositoryEID
}

// FormatDiff formats DiffContent to make it parse-able by gh/gh
func (s SuggestedFixFile) FormatDiff() []byte {
	diff := s.DiffContent
	// git diff header format: diff --git a/file b/file
	newDiff := []byte(fmt.Sprintf("diff --git a/%[1]s b/%[1]s\n", s.FilePath))
	newDiff = append(newDiff, diff...)
	return newDiff
}

func (s *SuggestedFixFile) BeforeSave() error {
	if s.FilePath == "" {
		return errors.New("FilePath cannot be empty")
	}
	s.FilePathHash = BuildFilePathHash(s.FilePath)
	return nil
}

func BuildFilePathHash(filePath string) []byte {
	h := sha256.New()
	h.Write([]byte(filePath))
	return h.Sum(nil)[:FilePathHashSize]
}
