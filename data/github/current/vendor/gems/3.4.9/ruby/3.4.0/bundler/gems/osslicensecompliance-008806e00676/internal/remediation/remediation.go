// Package remediation handles alert remediation flows including applying licenses to policies
// and closing alerts when remediated.
package remediation

import (
	"context"

	"github.com/github/osslicensecompliance/internal/application"
)

// GetDistributionContextForRepository is a placeholder. The idea is that this function will,
// when we do the multiple policy work, find out what the distribution context for the given repository is.
// For now, we just return "distributed" as that is the only context we have.
func GetDistributionContextForRepository(ctx context.Context, app *application.Application, repositoryID uint64) (string, error) {
	return "distributed", nil
}

type jsonEventBody interface {
	ToJSON() ([]byte, error)
}
