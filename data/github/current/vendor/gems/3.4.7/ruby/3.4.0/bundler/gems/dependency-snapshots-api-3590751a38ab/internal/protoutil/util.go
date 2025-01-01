package protoutil

import (
	"github.com/golang/protobuf/proto" //nolint:staticcheck
)

// Unmarshal parses a wire-format message in b and places the decoded results in m.
func Unmarshal(b []byte, m proto.Message) error {
	return proto.Unmarshal(b, m)
}

// Marshal returns the wire-format encoding of m.
func Marshal(m proto.Message) ([]byte, error) {
	return proto.Marshal(m)
}
