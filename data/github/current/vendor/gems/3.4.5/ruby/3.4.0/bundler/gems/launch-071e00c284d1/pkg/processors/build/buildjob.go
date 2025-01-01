package build

import (
	"github.com/github/launch/services/deploy/workflowinvoker"
)

// InvocationJob is the shape of an aqueduct message
type Job struct {
	Invocation workflowinvoker.Invocation `json:"invocation"`
}
