//go:build !dev

package repositories

import (
	"github.com/github/actions-usage-metrics/internal/config"
)

func SetRepositoriesClient(cfg config.HttpConfig) error {
	return setRepositoriesClient(cfg)
}
