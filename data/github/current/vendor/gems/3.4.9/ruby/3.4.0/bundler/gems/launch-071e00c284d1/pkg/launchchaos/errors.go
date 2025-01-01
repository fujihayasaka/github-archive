package launchchaos

import (
	"fmt"
)

func NewUnknownScenarioError(s string) error {
	return fmt.Errorf("scenario %q is not known to launchchaos", s)
}
