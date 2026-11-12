package cosmosdb

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/jobs/store"
)

// CreateProgress creates a new progress update in the database.
func (s *CosmosJobsStore) CreateProgress(ctx context.Context, item *progress.Progress) (*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.CreateProgress")
	defer span.End()

	pk := jobPK(item.AssignmentID, item.JobID)

	if item.CreatedAt == 0 {
		item.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(item)
	if err != nil {
		return nil, err
	}

	response, err := s.progress.CreateItem(ctx, pk, marshalled, nil)
	if err != nil {
		return nil, err
	}

	var newProgress *progress.Progress
	err = json.Unmarshal(response.Value, &newProgress)
	if err != nil {
		return nil, err
	}

	return item, nil
}

// GetProgress retrieves a progress update by its ID.
func (s *CosmosJobsStore) GetProgress(ctx context.Context, assignmentID, jobID, id string) (*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetProgress")
	defer span.End()

	pk := jobPK(assignmentID, jobID)

	response, err := s.progress.ReadItem(ctx, pk, id, nil)
	if err != nil {
		return nil, err
	}

	var item *progress.Progress
	err = json.Unmarshal(response.Value, &item)
	if err != nil {
		return nil, err
	}

	return item, nil
}

// BatchCreateProgress creates multiple progress updates in a single operation.
func (s *CosmosJobsStore) BatchCreateProgress(ctx context.Context, items []*progress.Progress) ([]*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.BatchCreateProgress")
	defer span.End()

	if len(items) == 0 {
		return items, nil
	}

	// confirm all items belong to the same assignment and job
	assignmentID := items[0].AssignmentID
	jobID := items[0].JobID
	for _, cmd := range items {
		if cmd.AssignmentID != assignmentID || cmd.JobID != jobID {
			return nil, store.NewErrBatchPartitionKeysMismatch()
		}
	}
	pk := jobPK(assignmentID, jobID)

	var created []*progress.Progress
	var batches []azcosmos.TransactionalBatch
	for chunk := range slices.Chunk(items, MaxOperationsInTransactionalBatch) {
		batch := s.progress.NewTransactionalBatch(pk)

		for _, item := range chunk {
			if item.CreatedAt == 0 {
				item.CreatedAt = time.Now().Unix()
			}

			marshalled, err := json.Marshal(item)
			if err != nil {
				return nil, err
			}

			batch.CreateItem(marshalled, nil)
		}
		batches = append(batches, batch)
	}

	var errs []error

	opts := &azcosmos.TransactionalBatchOptions{
		EnableContentResponseOnWrite: true,
	}

	for _, batch := range batches {
		response, err := s.progress.ExecuteTransactionalBatch(ctx, batch, opts)
		if err != nil {
			return nil, err
		}

		if response.Success {
			for _, result := range response.OperationResults {
				var item *progress.Progress
				err = json.Unmarshal(result.ResourceBody, &item)
				if err != nil {
					return nil, err
				}
				created = append(created, item)
			}
			continue
		}

		// Batching follows an all-or-nothing approach. If any operation fails,
		// the entire batch is considered failed.
		// If an operation does fail, that operation will have the "real" status
		// code corresponding to the error. All the other operations will have a
		// 424 status code (failed dependency) to indicate they were not executed
		// because of the failure of another operation.
		for _, result := range response.OperationResults {
			if result.StatusCode == http.StatusFailedDependency {
				continue // skip failed dependency errors (see comment above)
			}
			errs = append(errs, goerrors.Errorf("failed to create progress update with status: %d", result.StatusCode))
		}
	}

	if len(errs) > 0 {
		return nil, errors.Join(store.NewErrBatchOperationFailed(), errors.Join(errs...))
	}

	return created, nil
}

// ListProgress retrieves all progress updates for a given assignment and job.
func (s *CosmosJobsStore) ListProgress(ctx context.Context, assignmentID, jobID string) ([]*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.ListProgress")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@assignment_id", Value: assignmentID},
			{Name: "@job_id", Value: jobID},
		},
	}

	query := "SELECT * FROM c WHERE c.assignment_id = @assignment_id AND c.job_id = @job_id"
	pager := s.progress.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[progress.Progress](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get progress updates: %w", err)
	}

	return items, nil
}

// ListProgressByNamespace retrieves all progress updates for a given
// assignment, job, and namespace.
func (s *CosmosJobsStore) ListProgressByNamespace(ctx context.Context, assignmentID, jobID string, namespaces []string) ([]*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.ListProgressByNamespace")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@assignment_id", Value: assignmentID},
			{Name: "@job_id", Value: jobID},
		},
	}

	query := "SELECT * FROM c WHERE c.assignment_id = @assignment_id AND c.job_id = @job_id"

	switch len(namespaces) {
	case 0:
		return []*progress.Progress{}, nil

	case 1:
		opt.QueryParameters = append(opt.QueryParameters, azcosmos.QueryParameter{Name: "@namespace", Value: namespaces[0]})
		query += " AND c.namespace = @namespace"

	default:
		placeholders := make([]string, len(namespaces))
		for i, ns := range namespaces {
			paramName := fmt.Sprintf("@namespace%d", i)
			opt.QueryParameters = append(opt.QueryParameters, azcosmos.QueryParameter{Name: paramName, Value: ns})
			placeholders[i] = paramName
		}
		query += fmt.Sprintf(" AND c.namespace IN (%s)", strings.Join(placeholders, ", "))
	}

	pager := s.progress.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[progress.Progress](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get progress updates: %w", err)
	}

	return items, nil
}

// ListProgressByNamespaceAndKind retrieves all progress updates for a given
// assignment, job, namespace, and kind.
func (s *CosmosJobsStore) ListProgressByNamespaceAndKind(ctx context.Context, assignmentID, jobID, namespace, kind string) ([]*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.ListProgressByNamespaceAndKind")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@assignment_id", Value: assignmentID},
			{Name: "@job_id", Value: jobID},
			{Name: "@namespace", Value: namespace},
			{Name: "@kind", Value: kind},
		},
	}

	query := "SELECT * FROM c WHERE c.assignment_id = @assignment_id AND c.job_id = @job_id AND c.namespace = @namespace AND c.kind = @kind"
	pager := s.progress.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[progress.Progress](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get progress updates: %w", err)
	}

	return items, nil
}

// UpdateProgress updates an existing progress update in the database.
func (s *CosmosJobsStore) UpdateProgress(ctx context.Context, item *progress.Progress) (*progress.Progress, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpdateProgress")
	defer span.End()

	pk := jobPK(item.AssignmentID, item.JobID)

	marshalled, err := json.Marshal(item)
	if err != nil {
		return nil, err
	}

	opts := &azcosmos.ItemOptions{EnableContentResponseOnWrite: true}
	if item.ETag != nil {
		opts.IfMatchEtag = item.ETag
	}

	response, err := s.progress.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return nil, store.NewErrPreconditionFailedOnUpdate()
		}
		return nil, err
	}

	var updated *progress.Progress
	err = json.Unmarshal(response.Value, &updated)
	if err != nil {
		return nil, err
	}

	return updated, nil
}
