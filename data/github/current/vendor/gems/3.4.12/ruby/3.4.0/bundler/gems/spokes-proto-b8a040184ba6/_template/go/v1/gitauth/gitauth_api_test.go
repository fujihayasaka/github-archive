package gitauth

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewHostStatus(t *testing.T) {
	var s *HostStatus

	s = OKHostStatus("dgit1", "localhost", "/a/b/c")
	assert.Equal(t, "dgit1", s.GetReplicaName())
	assert.Equal(t, "localhost", s.GetHost())
	assert.Equal(t, "/a/b/c", s.GetPath())
	assert.Nil(t, s.GetErrorResult())
	assert.NotNil(t, s.GetOkResult())

	s = FailedHostStatus("dgit1", "localhost", "/a/b/c", "boom")
	assert.Equal(t, "dgit1", s.GetReplicaName())
	assert.Equal(t, "localhost", s.GetHost())
	assert.Equal(t, "/a/b/c", s.GetPath())
	assert.Equal(t, "boom", s.GetErrorResult().GetErrorMessage())
	assert.Nil(t, s.GetOkResult())
}
