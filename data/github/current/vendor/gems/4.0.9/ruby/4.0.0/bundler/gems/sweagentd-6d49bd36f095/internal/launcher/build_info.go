package launcher

// runtimeSubmoduleSHA is the git SHA of the runtime submodule at build time.
// It is injected via -ldflags "-X github.com/github/sweagentd/internal/launcher.runtimeSubmoduleSHA=..."
var runtimeSubmoduleSHA string
