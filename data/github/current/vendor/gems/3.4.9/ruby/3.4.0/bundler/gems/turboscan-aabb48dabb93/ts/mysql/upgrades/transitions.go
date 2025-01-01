// Package upgrades contains a library for building database transitions.
package upgrades

import (
	"context"
)

type transitions struct {
	items       map[uint]builder
	versionFunc func() uint
	step        uint64
}

type Builder interface {
	Version(version uint) Builder
	Step(step uint64) Builder
	Build(env *Env, opts *Opts) (map[uint]func(ctx context.Context) error, error)
	Simple(stmts ...string) Builder
	Function(tableName string, fn func(ctx context.Context, db DB, start, end uint64) error) Builder
	Batched(tableName string, stmt string) Builder
}

// Transitions stores registered transitions, ready to be built and sent to dbmigrator to be run.
func Transitions() Builder {
	return &transitions{
		items:       map[uint]builder{},
		versionFunc: mustGetVersion,
		step:        10000,
	}
}

// Version allows you to specify a version that will be used instead of the filename the transition is declared in.
func (t *transitions) Version(version uint) Builder {
	clone := *t
	clone.versionFunc = func() uint { return version }
	return &clone
}

// Step overrides the default step size of a batched transition.
func (t *transitions) Step(step uint64) Builder {
	clone := *t
	clone.step = step
	return &clone
}

func (t *transitions) add(fn builder) Builder {
	t.items[t.versionFunc()] = fn
	return t
}

type builder func(env *Env, opt *Opts) (func(ctx context.Context) error, error)

// Build builds the transitions that have been registered, ready for use by the dbmigrator library.
func (t *transitions) Build(env *Env, opts *Opts) (map[uint]func(ctx context.Context) error, error) {
	tr := make(map[uint]func(ctx context.Context) error)
	for version, build := range t.items {
		fn, err := build(env, opts)
		if err != nil {
			return nil, err
		}
		tr[version] = fn
	}
	return tr, nil
}
