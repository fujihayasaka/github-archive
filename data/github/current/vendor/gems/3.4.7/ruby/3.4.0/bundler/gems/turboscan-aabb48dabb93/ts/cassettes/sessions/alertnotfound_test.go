package sessions_test

import (
	"testing"

	"github.com/github/turboscan/ts/cassettes"
)

func TestAlertNotFound(t *testing.T) {
	session := cassettes.NewSession(t)
	session.Replay(t, "code-scanning/alert-not-found.yml")
}
