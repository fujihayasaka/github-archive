package types

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

const (
	name  = "Example Exampleson"
	email = "example@example.com"
)

func TestNewAttribution(t *testing.T) {
	now := time.Now()
	ts := NewTimestamp(now)

	a := NewAttribution(name, email, now)
	require.Equal(t, &Attribution{Name: name, Email: email, Date: ts}, a)
}
