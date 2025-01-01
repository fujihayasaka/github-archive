package transitions

import (
	"fmt"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestTransitionFileName(t *testing.T) {
	// This is a test and documentation showing how a transition  with a input from file can be used
	// This can also be used to test the transition on codespaces dev environment.
	// Skipping this since it is not needed for CI pipeline.
	t.SkipNow()
	cmd := exec.Command("bash", "./script/transition", "--dry_run=true --type=remove_by_target_cost_center_docs --use_default_input_file=true")
	cmd.Dir = "/workspaces/billing-platform"
	stdoutStderr, err := cmd.CombinedOutput()
	assert.EqualError(t, err, "exit status 1")
	fmt.Printf("Transition output: %v\n", string(stdoutStderr))
	assert.Contains(t, string(stdoutStderr), "customer not found: 112233")
}
