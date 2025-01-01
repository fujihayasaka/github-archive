package ts

import (
	"crypto/sha256"
	"encoding/binary"
)

type ConfigurationID uint64

type Configuration struct {
	BaseModel
	ID ConfigurationID `verify:"ignore"`

	RepositoryID RepositoryEID
	Ref          Ref
	ToolID       ToolID
	Category     Category
	Hash         []byte
}

func uint64ToBytes(x uint64) []byte {
	a := make([]byte, 8)
	binary.BigEndian.PutUint64(a, x)
	return a
}

func (c *Configuration) UpdateHash() {
	separator := []byte{0}
	h := sha256.New()
	h.Write(uint64ToBytes(uint64(c.RepositoryID)))
	h.Write(separator)
	h.Write(c.Ref)
	h.Write(separator)
	h.Write(uint64ToBytes(uint64(c.ToolID)))
	h.Write(separator)
	h.Write([]byte(c.Category))

	c.Hash = h.Sum(nil)
}

func (c *Configuration) BeforeSave() error {
	c.UpdateHash()
	return nil
}
