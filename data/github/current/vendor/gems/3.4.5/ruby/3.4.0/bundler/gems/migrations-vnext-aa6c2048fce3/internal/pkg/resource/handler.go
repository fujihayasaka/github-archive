package resource

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	v1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
)

type (
	// handler is the interface that wraps the basic methods to process a single resource.
	//
	// A resource handler is responsible for loading a resource into gh/gh.
	// The methods in the interface describe the workflow of loading a resource:
	//
	// 1. resourceID: returns the resource ID that uniquely identifies the resource in the source system.
	//
	// 2. skip: returns true if the resource should be skipped altogether, no further processing is needed.
	//
	// 3. dependencies: returns the dependencies for the resource that need to be fetched before loading
	//                  the resource. The dependencies are returned as a map from the resource IDs (source) to their
	//                  transformed values (target). These fetched dependencies will be passed to the next methods.
	//
	// 4. transform: transforms the resource, i.e: rewrite URLs, etc.
	//
	// 5. load: loads the resource, i.e: calls the import API.
	//
	// 6. newTransformedIDs: returns the new transformed values to store that will be used by dependants. E.g:
	//                       if the resource is an issue, and the issue is created in the target system, the
	//                       issue ID in the target system will be returned referenced by its source resource ID.
	//
	// Please, see LoaderImpl.handle for more details on how the handler is used.
	handler interface {
		// resourceID returns the resource ID for the resource
		resourceID() string
		// skip returns true if the resource should be skipped altogether
		skip() bool
		// dependencies returns the dependencies for the resource that need to be fetched before loading
		dependencies() (*transformedDeps, error)
		// transform transforms the resource, i.e: rewrite URLs, etc.
		// `resolved` is the set of resolved dependencies, i.e: a map from source IDs to their target value
		transform(resolved resolvedIDsByResource) error
		// load loads the resource, i.e: calls the import API. `resolved` is the set of resolved dependencies
		load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error
		// get the new transformed values to store that will be used by dependants at resolution time
		newResolvedIDs() resolvedIDsByResource
	}

	// batchHandler is the interface that wraps the basic methods to process a batched resource.
	//
	// The main difference between a batchHandler and a handler is that a batchHandler is responsible for loading
	// multiple resources at once.
	//
	// A batch resource has a batch ID that uniquely identifies the batch of resources in the source system.
	// It also has a list of item IDs that uniquely identify the items in the batch.
	//
	// Batches support partial loading, i.e: if a batch fails to load some items but not all, when the batch is retried,
	// only the failed items will be reloaded. In order to do that, the batchHandler needs to keep track of the items
	// that failed to load. This is done in two ways:
	//
	// 1. When individual items fail to load, the batchHandler should return a PartialBatchError with the error that
	//    caused the failure and the set of items that failed to load.
	// 2. This will be used the next time the batch is retried to skip the items that failed to load. In order to do that,
	//    a set of already-loaded item IDs is passed to the dependencies and transform methods.
	//
	// Anything else is similar to handler. Please, see LoaderImpl.handleBatch for more details on how the handler is used.
	batchHandler interface {
		// batchID returns the resource ID for the batch
		batchID() string
		// itemIDs returns the IDs of the items in the batch
		itemIDs() []string
		// dependencies returns the dependencies the batch, `loaded` is the set of items that are already loaded
		// and should  be skipped
		dependencies(loaded idSet) (*transformedDeps, error)
		// transform transforms the resource(s), i.e: rewrite URLs, etc.
		// `loaded` is the set of items that are already loaded.
		// `resolved` is the set of resolved dependencies, i.e: a map from a source ID to its transformed value
		transform(loaded idSet, resolved resolvedIDsByResource) error
		// load loads the resource, i.e: calls the import API,
		load(ctx context.Context, importer client.Importer, loaded idSet, resolved resolvedIDsByResource) error
		// get the new transformed values to store that will be used by dependants at resolution time
		newResolvedIDs() resolvedIDsByResource
	}

	// baseHandler is the base implementation of the handler interface that provides default implementations
	baseHandler struct {
		logger log.Logger
	}

	// baseBatchHandler is the base implementation of the batchHandler interface that provides default implementations
	baseBatchHandler struct {
		logger log.Logger
	}

	// transformedDeps is a struct that contains the IDs of the dependencies that need to be fetched to
	// load a resource
	transformedDeps struct {
		int64Deps set.Set[string]
		strDeps   set.Set[string]
	}

	// transformedValues is a struct that contains the transformed values for a resource
	transformedValues struct {
		int64Val int64
		strVal   string
	}

	// resolvedIDsByResource is a map from resource IDs to their transformedValues
	resolvedIDsByResource map[string]*transformedValues

	// idSet is a set of resource IDs
	idSet map[string]struct{}

	// PartialBatchError is an error that occurs when a batch fails to load some items but not all
	// it contains the error that caused the failure and the set of items (resource IDs) that failed to load
	PartialBatchError struct {
		err         error
		failedItems idSet
	}
)

func newTransformedDeps() *transformedDeps {
	return &transformedDeps{
		int64Deps: set.New[string](),
		strDeps:   set.New[string](),
	}
}

// dependencies is the default implementation of dependencies, it always returns nil, nil
func (b *baseHandler) dependencies() (*transformedDeps, error) {
	return nil, nil
}

// skip is the default implementation of skip, it always returns false
func (b *baseHandler) skip() bool {
	return false
}

// transform is the default implementation of transform, it always returns nil
func (b *baseHandler) transform(_ resolvedIDsByResource) error {
	return nil
}

// newTransformedIDs is the default implementation of newTransformedIDs, it always returns nil
func (b *baseHandler) newResolvedIDs() resolvedIDsByResource {
	return nil
}

// transform is the default implementation of transform, it always returns nil
func (b *baseBatchHandler) transform(_ idSet, _ resolvedIDsByResource) error {
	return nil
}

// Error returns the error message for the partial batch error
func (e *PartialBatchError) Error() string {
	return fmt.Sprintf("partial batch error: %v", e.err)
}

// toFailedItems returns the items that failed to load from a v1.BatchValidationError slice
func toFailedItems[T any](batchErrors []*v1.BatchValidationError, items []T) ([]T, error) {
	var failedElements []T
	for _, failed := range batchErrors {
		idx := int(failed.BatchIndex)
		if idx < 0 || idx >= len(items) {
			return nil, fmt.Errorf("invalid batch index %d", idx)
		}
		failedElements = append(failedElements, items[idx])
	}
	return failedElements, nil
}

// toFailedErrors returns an error from a v1.BatchValidationError slice
func toFailedErrors(batchErrors []*v1.BatchValidationError) error {
	var err error
	for _, failed := range batchErrors {
		err = errors.Join(err, fmt.Errorf("failed to load item[%d]: %s", failed.BatchIndex, failed.ErrorMessage))
	}
	return err
}

// String returns a string representation of the resolvedIDsByResource
func (t resolvedIDsByResource) String() string {
	var strs []string
	for k, v := range t {
		strs = append(strs, fmt.Sprintf("%s:[int64: %d, str: '%s']", k, v.int64Val, v.strVal))
	}
	return strings.Join(strs, " ")
}
