package ts

import (
	"crypto/sha256"
	"encoding/binary"
)

const SnippetHashSize = sha256.Size

type SnippetID uint64
type SnippetHash [SnippetHashSize]byte

// Snippet is a code snippet used in a repo.
type Snippet struct {
	BaseModel
	ID           SnippetID `verify:"ignore"`
	RepositoryID RepositoryEID
	Region       Region `gorm:"EMBEDDED"`
	Text         string
	Hash         []byte // 32byte sha256
}

// uint32ToBytes converts an unsigned 32bit int into a 4-length byte slice
func uint32ToBytes(x uint32) []byte {
	a := make([]byte, 4)
	binary.BigEndian.PutUint32(a, x)
	return a
}

func (s *Snippet) GetHash() SnippetHash {
	var hash SnippetHash
	copy(hash[:], s.Hash[:sha256.Size])
	return hash
}

func (s *Snippet) UpdateHash() SnippetHash {
	// SHA256(Region, Text)
	var hash SnippetHash
	del := []byte{0}
	h := sha256.New()
	h.Write(uint32ToBytes(s.Region.StartColumn))
	h.Write(del)
	h.Write(uint32ToBytes(s.Region.EndColumn))
	h.Write(del)
	h.Write(uint32ToBytes(s.Region.StartLine))
	h.Write(del)
	h.Write(uint32ToBytes(s.Region.EndLine))
	h.Write(del)
	h.Write([]byte(s.Text))

	s.Hash = h.Sum(nil)[:sha256.Size]
	copy(hash[:], s.Hash)
	return hash
}
