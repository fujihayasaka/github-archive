package ctxkey_test

import (
	"testing"

	"github.com/github/launch/pkg/mu/ctxkey"
)

func TestKey(t *testing.T) {
	k := ctxkey.New("foo")

	if k.Name() != "foo" {
		t.Error("expected 'foo' name")
	}
}
