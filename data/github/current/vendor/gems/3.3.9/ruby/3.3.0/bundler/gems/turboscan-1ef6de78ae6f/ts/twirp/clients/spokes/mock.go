package spokes

import (
	"context"
	"path/filepath"

	"github.com/github/turboscan/ts"
)

type MockSpokes struct {
	contents map[string][]byte
}

func (m *MockSpokes) key(file Filename, c CommitOID) string {
	return filepath.Join(string(c), string(file))
}

func (m *MockSpokes) AddFile(f Filename, c CommitOID, b []byte) {
	if m.contents == nil {
		m.contents = make(map[string][]byte)
	}
	m.contents[m.key(f, c)] = b
}
func (m *MockSpokes) GetFile(_ context.Context, r ts.RepositoryEID, f Filename, c CommitOID) ([]byte, error) {
	if m.contents == nil {
		m.contents = make(map[string][]byte)
	}
	v, ok := m.contents[m.key(f, c)]
	if ok {
		return v, nil
	} else {
		return nil, ErrFileNotFound
	}
}

var _ Spokes = &MockSpokes{}
