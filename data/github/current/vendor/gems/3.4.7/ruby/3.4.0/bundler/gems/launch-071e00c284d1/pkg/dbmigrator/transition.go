package dbmigrator

import (
	"context"
	"fmt"
	"time"
)

// Transitioner is responsible for adding transitions for a migrator.
type Transitioner struct {
	versions map[uint]*Transition
}

func NewTransitioner() *Transitioner {
	return &Transitioner{make(map[uint]*Transition)}
}

// AddTransition adds a new transition to run for a specific migration version.
func (t *Transitioner) Add(version uint, fn MigrationFunc) error {
	if _, ok := t.versions[version]; ok {
		err := fmt.Errorf("transition already exists for version %d", version)
		return err
	}

	t.versions[version] = NewTransition(version, fn)

	return nil
}

func (t *Transitioner) Get(version uint) (*Transition, bool) {
	transition, ok := t.versions[version]
	return transition, ok
}

func (t *Transitioner) LatestTransition() (*Transition, uint) {
	var latestVersion uint
	var latestTransition *Transition
	for v, tt := range t.versions {
		if v > latestVersion {
			latestVersion = v
			latestTransition = tt
		}
	}
	return latestTransition, latestVersion
}

type Transition struct {
	schemaVersion uint
	migrationFn   MigrationFunc
	startedAt     time.Time
	endedAt       time.Time
}

func NewTransition(schemaVersion uint, fn MigrationFunc) *Transition {
	return &Transition{
		schemaVersion: schemaVersion,
		migrationFn:   fn,
	}
}

func (t *Transition) Run(ctx context.Context) error {
	t.startedAt = time.Now().UTC()
	defer func() {
		t.endedAt = time.Now().UTC()
	}()

	err := t.migrationFn(ctx)
	if err != nil {
		return err
	}

	return nil
}
