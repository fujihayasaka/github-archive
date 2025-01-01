// Package configuration contains a service that stores the configuration referenced by a code scanning analysis.
package configuration

import (
	"context"

	"github.com/github/turboscan/ts/o11y/otelgorm"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"

	"github.com/jinzhu/gorm"
)

// Service handles interactions with Configurations.
type Service struct {
	db *gorm.DB
}

// NewService returns a service to store the configurations that results have been submitted for.
func NewService(db *gorm.DB) *Service {
	return &Service{
		db: db,
	}
}

func (t *Service) FindOrCreate(ctx context.Context, configuration *ts.Configuration) error {
	db := otelgorm.SetSpanToGorm(ctx, t.db)

	configuration.UpdateHash()

	err := db.FirstOrCreate(configuration, ts.Configuration{RepositoryID: configuration.RepositoryID, Hash: configuration.Hash}).Error

	return errors.Wrap(err, "error finding or creating configuration")
}
