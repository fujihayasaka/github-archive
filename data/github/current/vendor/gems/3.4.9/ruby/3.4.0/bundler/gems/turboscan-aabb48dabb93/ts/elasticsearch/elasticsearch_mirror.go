package elasticsearch

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
)

type updateByQuery struct {
	query     elastic.Query
	script    *elastic.Script
	conflicts string
}

type Operation struct {
	Name      string
	UpdateCmd *updateByQuery
	// We need to take the requests instead of the command because the requests are cleared after a Do operation
	BulkRequests []elastic.BulkableRequest
}

// mirrorOperation tries to run the operation on all indexes that are currently aliased
// to our current read alias. It will carry on and only log errors.
// mirrorOperation also runs the operation on the secondary (cluster) if configured.
func (e *Service) mirrorOperation(ctx context.Context, cfg *IndexConfig, o Operation) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "mirror-operation")()

	if e.SkipMirroring {
		return
	}

	// If we are in a migration scenario then we need to duplicate the operation on any index that we are
	// reading from, but not writing to.
	// This is non-fatal however as it should only be needed temporarily
	mirrorIndexes, err := e.getMirrorIndexes(ctx, cfg)
	if err != nil {
		appctx.Logger(ctx).WithError(err).Error("failed to get mirror indexes for " + o.Name)
		return
	}
	for _, index := range mirrorIndexes {
		err = e.doOnIndex(ctx, e.es, index, o)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("failed to mirror command", kvp.String("gh.turboscan.mirror_command", o.Name), kvp.String("gh.turboscan.mirror_index", index))
		}
	}

	if e.secondary != nil {
		index := cfg.name
		err = e.doOnIndex(ctx, e.secondary, index, o)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("failed to mirror command to secondary cluster", kvp.String("gh.turboscan.mirror_command", o.Name), kvp.String("gh.turboscan.mirror_index", index))
		}
	}
}

// doOnIndex executes the specified operation on the given index returning a potential error
func (e *Service) doOnIndex(ctx context.Context, es *elastic.Client, index string, o Operation) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "do-on-index")()

	if o.UpdateCmd != nil {
		update := es.UpdateByQuery().
			Index(index).
			Query(o.UpdateCmd.query).
			Script(o.UpdateCmd.script).
			Conflicts(o.UpdateCmd.conflicts)

		_, err := update.Do(ctx)
		if err != nil {
			return err
		}
	}
	if len(o.BulkRequests) > 0 {
		bulk := es.Bulk().Index(index)
		bulk.Add(o.BulkRequests...)
		_, err := bulk.Do(ctx)
		if err != nil {
			return err
		}
	}
	return nil
}

// getMirrorIndexes returns the indexes that are aliased to the current read alias, but not
// the write alias. This will generally be empty but return the old index when we are in an
// upgrade context.
func (e *Service) getMirrorIndexes(ctx context.Context, cfg *IndexConfig) ([]string, error) {

	aliases, err := e.es.Aliases().Do(ctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch aliases")
	}

	var readIndexes, writeIndexes []string
	if cfg.name == cfg.readAlias {
		// we're not relying on aliases for reading
		readIndexes = []string{cfg.name}
	} else {
		readIndexes = aliases.IndicesByAlias(cfg.readAlias)
	}

	if cfg.name == cfg.writeAlias {
		// we're not relying on aliases for writing
		writeIndexes = []string{cfg.name}
	} else {
		writeIndexes = aliases.IndicesByAlias(cfg.writeAlias)
	}
	if len(writeIndexes) != 1 {
		return nil, errors.Errorf("expected 1 index to be aliased to %s but found %d", cfg.writeAlias, len(writeIndexes))
	}

	mirrorIndexes := make(map[string]bool)
	for _, index := range readIndexes {
		if index != writeIndexes[0] {
			mirrorIndexes[index] = true
		}
	}

	for _, index := range aliases.IndicesByAlias(cfg.mirrorAlias) {
		if index != writeIndexes[0] {
			mirrorIndexes[index] = true
		}
	}

	return maps.Keys(mirrorIndexes), nil
}
