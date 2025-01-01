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

// NewTransitioner creates and returns a pointer to a Transitioner with a new versions map initialized.
func NewTransitioner() *Transitioner {
	return &Transitioner{make(map[uint]*Transition)}
}

// Add adds a new transition to run for a specific migration version.
func (t *Transitioner) Add(version uint, fn MigrationFunc) error {
	if _, ok := t.versions[version]; ok {
		return fmt.Errorf("transition already exists for version %d", version)
	}

	t.versions[version] = NewTransition(version, fn)

	return nil
}

// GetTransition returns the Transition object and a boolean success for a given version number.
func (t *Transitioner) GetTransition(version uint) (*Transition, bool) {
	transition, ok := t.versions[version]
	return transition, ok
}

// LatestTransition returns the Transition with the latest version number in the versions map.
func (t *Transitioner) LatestTransition() *Transition {
	var latestVersion uint
	var latestTransition *Transition
	for v, tt := range t.versions {
		if v > latestVersion {
			latestVersion = v
			latestTransition = tt
		}
	}

	// This should be unnecessary. the transition's schema should always align to the version
	// used to store it in the versions map
	latestTransition.schemaVersion = latestVersion

	return latestTransition
}

// Transition defines a struct that represents a data transition.
type Transition struct {
	schemaVersion uint
	migrationFn   MigrationFunc
	startedAt     time.Time
	endedAt       time.Time
}

// NewTransition creates and returns a pointer to a Transition with the given schemaVersion and MigrationFunc.
func NewTransition(schemaVersion uint, fn MigrationFunc) *Transition {
	return &Transition{
		schemaVersion: schemaVersion,
		migrationFn:   fn,
	}
}

// Run runs the migrationFn for a Transition.
func (t *Transition) Run(ctx context.Context) error {
	t.startedAt = time.Now().UTC()
	defer func() {
		t.endedAt = time.Now().UTC()
	}()

	err := t.migrationFn(ctx)
	if err != nil {
		return fmt.Errorf("running transition: %w", err)
	}

	return nil
}
