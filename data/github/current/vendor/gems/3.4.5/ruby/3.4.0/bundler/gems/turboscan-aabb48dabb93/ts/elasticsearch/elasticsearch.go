// Package elasticsearch implements our ElasticSearch cache.
package elasticsearch

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/olivere/elastic"
	"github.com/pkg/errors"
)

const MAX_ES_OFFSET = 10000

// Service is a wrapper around the generic ElasticSearch client.
// Most of its methods, however, are specific to the pre-configured indices and Turboscan use-cases
type Service struct {
	es            *elastic.Client
	secondary     *elastic.Client // Client for secondary cluster. This is used to migrate cross-cluster, like ES5 to ES8, or for fail-over.
	indexSettings interface{}
	SkipMirroring bool // When true the indexer will not mirror documents to another aliased index
}

func NewService(ctx context.Context, username, password, addr string, settings interface{}) (*Service, error) {
	appctx.Logger(ctx).Info("Connecting to Elasticsearch...", kvp.String("gh.turboscan.elasticsearch_address", addr))

	es, err := elastic.DialContext(
		ctx,
		elastic.SetURL(addr),
		elastic.SetBasicAuth(username, password),
		elastic.SetSniff(false),
		elastic.SetHealthcheck(false),
		elastic.SetRetrier(elastic.NewBackoffRetrier(elastic.NewExponentialBackoff(10*time.Millisecond, time.Second))),
	)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create Elasticsearch client")
	}

	return &Service{
		es:            es,
		indexSettings: settings,
	}, nil
}

func (e *Service) SetSecondary(username, password, addr string) error {
	es, err := elastic.NewClient(
		elastic.SetURL(addr),
		elastic.SetBasicAuth(username, password),
		elastic.SetSniff(false),
		elastic.SetHealthcheck(false),
		elastic.SetRetrier(elastic.NewBackoffRetrier(elastic.NewExponentialBackoff(10*time.Millisecond, time.Second))),
	)
	if err != nil {
		return errors.Wrap(err, "failed to create secondary Elasticsearch client")
	}

	e.secondary = es

	return nil
}

func (e *Service) SetSkipMirroring(skipMirroring bool) {
	e.SkipMirroring = skipMirroring
}

func getIndexConfig(target ts.Index) (*IndexConfig, error) {
	switch target {
	case ts.Index_OrgLevel:
		return orgLevelIndex, nil
	default:
		return nil, errors.New("unknown index type")
	}
}

// CreateIndex creates the specified index in the ElasticSearch cluster.
// If replace is true, any existing index with the same name will be deleted.
func (e *Service) CreateIndex(ctx context.Context, index ts.Index, replace bool) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "create-index")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}

	exists, err := e.es.IndexExists(cfg.name).Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to check if index exists")
	}

	if exists {
		if replace {
			deleteIndex, err := e.es.DeleteIndex(cfg.name).Do(ctx)
			if err != nil {
				return errors.Wrap(err, "failed to delete index")
			}
			if !deleteIndex.Acknowledged {
				return errors.New("could not acknowledge index deletion")
			}
		} else {
			return nil
		}
	}

	var mappings interface{}
	if docMappings, ok := cfg.mapping["mappings"].(map[string]interface{}); ok {
		mappings = docMappings["doc"]
	}

	createIndex := e.es.CreateIndex(cfg.name).BodyJson(
		map[string]interface{}{
			"settings": e.indexSettings,
			"mappings": mappings,
		},
	)
	createIndexResult, err := createIndex.Do(ctx)

	if err != nil {
		return errors.Wrap(err, "failed to create index")
	}
	if !createIndexResult.Acknowledged {
		return errors.New("could not acknowledge index creation")
	}

	// If the read and write aliases don't exist on the cluster,
	// we should create them now.
	aliases, err := e.es.Aliases().Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to fetch aliases")
	}
	writeAliases := aliases.IndicesByAlias(cfg.writeAlias)
	if len(writeAliases) == 0 {
		addAlias, err := e.es.Alias().Add(cfg.name, cfg.writeAlias).Do(ctx)
		if err != nil {
			return errors.Wrap(err, "failed to add write alias")
		}
		if !addAlias.Acknowledged {
			return errors.New("could not acknowledge write alias addition")
		}
	}
	readAliases := aliases.IndicesByAlias(cfg.readAlias)
	if len(readAliases) == 0 {
		addAlias, err := e.es.Alias().Add(cfg.name, cfg.readAlias).Do(ctx)
		if err != nil {
			return errors.Wrap(err, "failed to add read alias")
		}
		if !addAlias.Acknowledged {
			return errors.New("could not acknowledge read alias addition")
		}
	}

	return nil
}

// IndexDocuments creates or updates the provided documents in the specified ElasticSearch index.
// changedLogicalAlertIds is optional map of logical alert IDs that have changed, used to instrument the changes to Insights.
func (e *Service) IndexDocuments(ctx context.Context, index ts.Index, docs []*ts.SearchDocument) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "index-documents")()

	// Break out early if nothing to index
	if len(docs) == 0 {
		return nil
	}

	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}

	if len(docs) == 1 {
		return e.indexDocument(ctx, cfg, docs[0])
	}

	bulk := e.es.Bulk().Index(cfg.writeAlias)
	bulkRequests := []elastic.BulkableRequest{}
	for _, doc := range docs {
		req := elastic.NewBulkIndexRequest().Id(strconv.FormatUint(doc.AlertID, 10)).Doc(doc)
		bulkRequests = append(bulkRequests, req)
	}
	bulk.Add(bulkRequests...)

	resp, err := bulk.Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to index documents")
	}
	if len(resp.Failed()) > 0 {
		appctx.Logger(ctx).Error("failed to index documents",
			kvp.Int("gh.turboscan.elasticsearch_index_failed.count", len(resp.Failed())),
			kvp.Int("gh.turboscan.elasticsearch_index_total.count", len(docs)),
			kvp.String("gh.turboscan.elasticsearch_index_error", resp.Failed()[0].Error.Reason))
		return errors.New("failed to index documents")
	}
	created, updated := 0, 0
	for idx, item := range resp.Indexed() {
		switch {
		case item.Result == "created":
			created++
		case item.Result == "updated":
			updated++
		default:
			doc := docs[idx]
			repositoryId, _ := strconv.Atoi(doc.RepositoryID)
			appctx.Logger(ctx).Error("unknown index result",
				kvp.String("gh.turboscan.index_result", item.Result), kvp.String("gh.turboscan.elasticsearch_index_result_id", item.Id),
				kvp.String("gh.turboscan.alert_id", fmt.Sprint(doc.AlertID)), ts.RepositoryEID(repositoryId).AsKVP())
		}
	}
	appctx.Logger(ctx).Info("indexing completed", kvp.Int("gh.turboscan.index_updated", updated), kvp.Int("gh.turboscan.index_created", created))
	appctx.Stats(ctx).Counter("es.indexing", stats.Tags{"result": "created"}, int64(created))
	appctx.Stats(ctx).Counter("es.indexing", stats.Tags{"result": "updated"}, int64(updated))

	// Mirror command in upgrade scenarios
	e.mirrorOperation(ctx, cfg, Operation{Name: "IndexDocuments", BulkRequests: bulkRequests})

	return nil
}

func (e *Service) indexDocument(ctx context.Context, cfg *IndexConfig, d *ts.SearchDocument) error {
	defer e.duration(ctx, "index-document")()

	indexCmd := e.es.Index().
		Index(cfg.writeAlias).
		Type("_doc").
		Id(fmt.Sprint(d.AlertID)).
		BodyJson(d)

	_, err := indexCmd.Do(ctx)
	if err != nil {
		if strings.Contains(err.Error(), "type=index_not_found_exception") {
			return ts.ErrIndexNotFound
		}
		if strings.Contains(err.Error(), "type=strict_dynamic_mapping_exception") {
			return ts.ErrStrictMapping
		}
		return errors.Wrap(err, "failed to index document")
	}

	// Mirror command in upgrade scenarios
	indexCmdMirrorRequest := elastic.NewBulkIndexRequest().
		Id(fmt.Sprint(d.AlertID)).
		Doc(d)
	e.mirrorOperation(ctx, cfg, Operation{Name: "indexDocument", BulkRequests: []elastic.BulkableRequest{indexCmdMirrorRequest}})

	return nil
}

// CountAllDocuments returns the total number of documents in the index.
func (e *Service) CountAllDocuments(ctx context.Context, index ts.Index) (int64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "count-documents")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return 0, err
	}

	result, err := e.es.Count().
		Index(cfg.name).
		Do(ctx)
	return result, errors.Wrap(err, "failed to count documents")
}

// Refresh forces a refresh of the specified ElasticSearch indices.
// As this is a slow operation, it should not be called frequently.
// https://www.elastic.co/guide/en/elasticsearch/reference/5.6/indices-refresh.html
func (e *Service) Refresh(ctx context.Context, index ts.Index) error {
	defer e.duration(ctx, "refresh-index")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}
	_, err = e.es.Refresh(cfg.name).Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to refresh index")
	}
	return nil
}

// SetReadAlias makes sure the configured read alias for the specified index exists and
// points to current index name only.
func (e *Service) SetReadAlias(ctx context.Context, index ts.Index) error {
	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}
	return e.setAlias(ctx, cfg.name, cfg.readAlias)
}

// SetWriteAlias makes sure the configured write alias for the specified index exists and
// points to current index name only.
func (e *Service) SetWriteAlias(ctx context.Context, index ts.Index) error {
	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}
	return e.setAlias(ctx, cfg.name, cfg.writeAlias)
}

// setAlias makes sure the specified alias exists and points to the specified index name only.
func (e *Service) setAlias(ctx context.Context, index, alias string) error {
	aliases, err := e.es.Aliases().Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to fetch aliases")
	}
	aliasedIndexes := aliases.IndicesByAlias(alias)

	// add the specified index to the alias
	updateAliasCmd := e.es.Alias()
	updateAliasCmd.Add(index, alias)

	// remove all other indexes from the alias
	for _, i := range aliasedIndexes {
		if i != index {
			updateAliasCmd.Remove(i, alias)
		}
	}
	updateAlias, err := updateAliasCmd.Do(ctx)
	if err != nil {
		return errors.Wrap(err, "failed to update aliases")
	}
	if !updateAlias.Acknowledged {
		return errors.New("could not acknowledge alias update")
	}
	return nil
}

// MigrationRequired returns true if the elastic search index should be migrated.
// Migration is done by reindexing all the alerts into the new index. This is not
// an instant process so while it is ongoing the new code will continue to read
// from the old index.
// We can detect whether we are in a migration scenario by looking at the read alias.
// If it is not mapped exclusively to the current index then we need to migrate.
func (e *Service) MigrationRequired(ctx context.Context, index ts.Index) (bool, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "migration-required")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return false, err
	}

	aliases, err := e.es.Aliases().Do(ctx)
	if err != nil {
		return false, errors.Wrap(err, "failed to fetch aliases")
	}

	// We're still considered to be in a migration if the mirror alias exists.
	mirrorIndexes := aliases.IndicesByAlias(cfg.mirrorAlias)
	if len(mirrorIndexes) > 0 {
		return true, nil
	}

	// If the index name is the same as the read alias then we do not use the migration framework yet.
	if cfg.name == cfg.readAlias {
		return false, nil
	}

	// Check the indexes associated with the read alias
	readIndexes := aliases.IndicesByAlias(cfg.readAlias)

	// If there is 0 indexes the the alias most likely hasnt been created
	// and we should migrate.
	// If there are more than 1 then there is at least one non-current index
	// and we should migrate.
	if len(readIndexes) != 1 {
		return true, nil
	}

	// Do the same for the write alias
	writeIndexes := aliases.IndicesByAlias(cfg.writeAlias)
	if len(writeIndexes) != 1 {
		return true, nil
	}

	// If there is only a single alias then we need to migrate if it isnt the
	// current index.
	return readIndexes[0] != cfg.name || writeIndexes[0] != cfg.name, nil
}

// StartMigration will set the write alias to point to the current index and also register when the migrated started.
func (e *Service) StartMigration(ctx context.Context, index ts.Index) (*time.Time, error) {
	cfg, err := getIndexConfig(index)
	if err != nil {
		return nil, err
	}

	aliases, err := e.es.Aliases().Do(ctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to fetch aliases")
	}
	aliasedIndexes := aliases.IndicesByAlias(cfg.writeAlias)

	// Update the write and mirror aliases
	updateAliasCmd := e.es.Alias()
	updateAliasCmd.Add(cfg.name, cfg.writeAlias)
	updateAliasCmd.Remove(cfg.name, cfg.mirrorAlias) // Remove a potentially existing mirror

	for _, i := range aliasedIndexes {
		if i != cfg.name {
			updateAliasCmd.Remove(i, cfg.writeAlias)
			updateAliasCmd.Add(i, cfg.mirrorAlias)
		}
	}
	updateAlias, err := updateAliasCmd.Do(ctx)
	if err != nil {
		return nil, errors.Wrap(err, "failed to update aliases")
	}
	if !updateAlias.Acknowledged {
		return nil, errors.New("could not acknowledge alias update")
	}

	return e.registerMigrationStart(ctx, index)
}

// registerMigrationStart will store a timestamp in the index mapping metadata if it is not already present.
func (e *Service) registerMigrationStart(ctx context.Context, index ts.Index) (*time.Time, error) {
	field := "turboscanMigrationStartedAt"
	timeLayout := time.RFC3339

	mappingMeta, err := e.getMappingMeta(ctx, index)
	if err != nil {
		return nil, errors.Wrap(err, "error looking up mapping meta field")
	}
	value, ok := mappingMeta[field].(string)

	if !ok {
		mappingMeta[field] = time.Now().UTC().Format(timeLayout)
		err = e.updateMappingMeta(ctx, index, mappingMeta)
		if err != nil {
			return nil, errors.Wrap(err, "could not update mapping meta field")
		}

		// Read the meta field that was just written and ensure it is there.
		mappingMeta, err = e.getMappingMeta(ctx, index)
		if err != nil {
			return nil, errors.Wrap(err, "error looking up mapping meta field")
		}
		value, ok = mappingMeta[field].(string)
		if !ok {
			return nil, errors.New("could not find the meta field")
		}
	}

	migratedStartedAt, err := time.Parse(timeLayout, value)
	if err != nil {
		return nil, errors.Wrap(err, "error parsing time from mapping meta field")
	}

	return &migratedStartedAt, nil
}

func (e *Service) getMappingMeta(ctx context.Context, index ts.Index) (map[string]interface{}, error) {
	defer e.duration(ctx, "get-mapping-meta")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return nil, err
	}
	return e.typelessGetMappingMeta(ctx, cfg.name)
}

func (e *Service) updateMappingMeta(ctx context.Context, index ts.Index, meta map[string]interface{}) error {
	defer e.duration(ctx, "update-mapping-meta-field")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}
	return e.typelessUpdateMappingMeta(ctx, cfg.name, meta)
}

// CompleteMigration completes the migration by switching the read alias to the current index and
// deleting any old indexes that we were reading from.
func (e *Service) CompleteMigration(ctx context.Context, index ts.Index, allowDelete bool) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	defer e.duration(ctx, "complete-migration")()

	cfg, err := getIndexConfig(index)
	if err != nil {
		return err
	}

	indexesToDelete, err := e.getMirrorIndexes(ctx, cfg)
	if err != nil {
		return err
	}

	err = e.SetReadAlias(ctx, index)
	if err != nil {
		return err
	}

	// Remove all pruned indexes
	if allowDelete && len(indexesToDelete) > 0 {
		deleteIndex, err := e.es.DeleteIndex().Index(indexesToDelete).Do(ctx)
		if err != nil {
			return errors.Wrap(err, "failed to delete indexes")
		}
		if !deleteIndex.Acknowledged {
			return errors.New("could not acknowledge index deletion")
		}
	}

	return nil
}

// GetDocument returns the document with the specified ID from the specified index.
// This is a helper function and is currently used for testing.
func (e *Service) GetDocument(ctx context.Context, index ts.Index, docID uint64) (*ts.SearchDocument, error) {

	cfg, err := getIndexConfig(index)
	if err != nil {
		return nil, err
	}
	get := e.es.Get().Id(fmt.Sprint(docID)).Index(cfg.readAlias).Type("_doc")
	result, err := get.Do(ctx)
	if err != nil {
		if elastic.IsNotFound(err) {
			return nil, nil
		}
		return nil, errors.Wrap(err, "failed to get ES document")
	}
	var doc *ts.SearchDocument
	err = json.Unmarshal(*result.Source, &doc)
	if err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal document from ES result")
	}
	return doc, nil
}

// isValidQueryString uses the ES validation API to check the syntax of query
func (e *Service) isValidQueryString(ctx context.Context, index *IndexConfig, query string) bool {
	validation, err := e.es.Validate(index.name).Q(query).Do(ctx)
	if err != nil {
		// If we couldn't validate the query, we assume it's ok and fall back to the execution results
		appctx.Logger(ctx).WithError(err).Error("failed to validate query",
			kvp.String("gh.elasticsearch.index", index.name), kvp.String("gh.elasticsearch.query", query))
		return true
	}
	if !validation.Valid {
		appctx.Stats(ctx).Counter("es.invalid_query.count", stats.Tags{"reason": "query_string"}, 1)
	}
	return validation.Valid
}

func (e *Service) isValidPagination(ctx context.Context, pagination ts.Pagination) bool {
	// Elastic search only allows offsets <= 10k otherwise it crashes.
	if pagination.Offset+pagination.Limit > MAX_ES_OFFSET {
		appctx.Stats(ctx).Counter("es.search.max_offset_hit", nil, 1)
		return false
	}
	return true
}

func (e *Service) duration(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		if !appctx.IsShuttingDown(ctx) {
			appctx.Stats(ctx).DistributionMs("es.request", stats.Tags{"method": method}, time.Since(start))
		}
	}
}
