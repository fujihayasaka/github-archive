package fromctx

import (
	"os"
	"testing"

	"github.com/simon-engledew/ctxkey"
)

var IsTest = testing.Testing()

type Environment string

// IsCodespaces is true if we are in a Codespace
var IsCodespaces = func() bool {
	_, codespaces := os.LookupEnv("CODESPACES")
	return codespaces
}()

// IsGitHubCodespace is true if we are in a github/github Codespace
var IsGitHubCodespace = func() bool {
	if !IsCodespaces {
		return false
	}
	_, err := os.Stat("/workspaces/github")
	return !os.IsNotExist(err)
}()

// IsDevcontainer is true if we are in a Devcontainer
var IsDevcontainer = func() bool {
	_, devcontainer := os.LookupEnv("DEVCONTAINER")
	return devcontainer
}()

// IsServerStartDebug is true if only one unicorn worker is available
// and checking feature flags during a twirp request will deadlock
var IsServerStartDebug = func() bool {
	if !IsGitHubCodespace {
		return false
	}
	_, serverStartDebug := os.LookupEnv("SERVER_START_DEBUG")
	return serverStartDebug
}()

func (e Environment) IsEnterprise() bool {
	return e == "enterprise"
}

func (e Environment) IsTest() bool {
	return e == "" && IsTest
}

func (e Environment) IsDevelopment() bool {
	return e == "development"
}

var Env = ctxkey.New[Environment]("")
