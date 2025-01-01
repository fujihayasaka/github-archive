// Package mocks provides mocks for testing.
package mocks

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	customersv1 "github.com/github/licensify/lib/monolith-twirp/customers/v1"
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
	twirpFeatures "github.com/github/monolith-twirp-features/core/v1"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/proto"
)

// MockDBReadWriter is a mock for dbReadWriter.
type MockDBReadWriter struct {
	mock.Mock
}

// DatabaseName returns the database name.
func (m *MockDBReadWriter) DatabaseName() string {
	return "MockDB"
}

// ContainerName returns the container name.
func (m *MockDBReadWriter) ContainerName() string {
	return "MockContainer"
}

// NewTransactionalBatch mocks an azcosmos.TransactionalBatch.
func (m *MockDBReadWriter) NewTransactionalBatch(partitionKey azcosmos.PartitionKey) azcosmos.TransactionalBatch {
	args := m.Called(partitionKey)
	batch, ok := args.Get(0).(azcosmos.TransactionalBatch)
	if !ok && args.Get(0) != nil {
		panic(fmt.Errorf("expected *azcosmos.TransactionalBatch but got %T", args.Get(0)))
	}
	return batch
}

// ExecuteTransactionalBatch mocks an execution of an azcosmos.TransactionalBatch.
func (m *MockDBReadWriter) ExecuteTransactionalBatch(ctx context.Context, batch azcosmos.TransactionalBatch, o *azcosmos.TransactionalBatchOptions) (azcosmos.TransactionalBatchResponse, error) {
	args := m.Called(ctx, batch, o)
	batchResponse, ok := args.Get(0).(azcosmos.TransactionalBatchResponse)
	if !ok && args.Get(0) != nil {
		panic(fmt.Errorf("expected *azcosmos.TransactionalBatchResponse but got %T", args.Get(0)))
	}
	return batchResponse, args.Error(1)
}

// UpsertItem mocks a db upsert.
func (m *MockDBReadWriter) UpsertItem(ctx context.Context, partitionKey azcosmos.PartitionKey, b []byte, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	args := m.Called(ctx, partitionKey, b, o)
	itemResponse, _ := args.Get(0).(azcosmos.ItemResponse)

	return itemResponse, args.Error(1)
}

// CreateItem mocks a db create.
func (m *MockDBReadWriter) CreateItem(ctx context.Context, partitionKey azcosmos.PartitionKey, b []byte, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	args := m.Called(ctx, partitionKey, b, o)
	itemResponse, _ := args.Get(0).(azcosmos.ItemResponse)

	return itemResponse, args.Error(1)
}

// NewQueryItemsPager is needed to satisfy the dbReadWriter interface, but returns nil.
func (m *MockDBReadWriter) NewQueryItemsPager(query string, partitionKey azcosmos.PartitionKey, o *azcosmos.QueryOptions) *runtime.Pager[azcosmos.QueryItemsResponse] {
	args := m.Called(query, partitionKey, o)
	pager, _ := args.Get(0).(*runtime.Pager[azcosmos.QueryItemsResponse])
	return pager
}

// ReadItem mocks a db read.
func (m *MockDBReadWriter) ReadItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	args := m.Called(ctx, partitionKey, id, o)
	itemResponse, _ := args.Get(0).(azcosmos.ItemResponse)
	return itemResponse, args.Error(1)
}

// DeleteItem mocks a db delete.
func (m *MockDBReadWriter) DeleteItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	args := m.Called(ctx, partitionKey, id, o)
	itemResponse, _ := args.Get(0).(azcosmos.ItemResponse)
	return itemResponse, args.Error(1)
}

// PatchItem mocks a db patch.
func (m *MockDBReadWriter) PatchItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, ops azcosmos.PatchOperations, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error) {
	args := m.Called(ctx, partitionKey, id, ops, o)
	itemResponse, _ := args.Get(0).(azcosmos.ItemResponse)
	return itemResponse, args.Error(1)
}

// MockMonolithAPI is a mock for the monolith-twirp OrganizationMembersAPI.
type MockMonolithAPI struct {
	mock.Mock
}

// GetUsers mocks the monolith-twirp UsersAPI.GetUsers method.
func (m *MockMonolithAPI) GetUsers(ctx context.Context, request *customersv1.GetUsersRequest) (*customersv1.GetUsersResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*customersv1.GetUsersResponse)
	return args0, args.Error(1)
}

// GetRepositoryInformation mocks the monolith-twirp RepositoriesAPI.GetRepositoryInformation method.
func (m *MockMonolithAPI) GetRepositoryInformation(ctx context.Context, request *repositoriesv1.GetRepositoryInformationRequest) (*repositoriesv1.GetRepositoryInformationResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*repositoriesv1.GetRepositoryInformationResponse)
	return args0, args.Error(1)
}

// MockFeatureFlagsAPI is a mock for the monolith-twirp FeaturesAPI.
type MockFeatureFlagsAPI struct {
	mock.Mock
}

// CheckActorFeature mocks the monolith-twirp FeaturesAPI.CheckActorFeature method.
func (m *MockFeatureFlagsAPI) CheckActorFeature(ctx context.Context, request *twirpFeatures.CheckActorFeatureRequest) (*twirpFeatures.CheckActorFeatureResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*twirpFeatures.CheckActorFeatureResponse)
	return args0, args.Error(1)
}

// CheckActorsFeature mocks the monolith-twirp FeaturesAPI.CheckActorsFeature method.
func (m *MockFeatureFlagsAPI) CheckActorsFeature(ctx context.Context, request *twirpFeatures.CheckActorsFeatureRequest) (*twirpFeatures.CheckActorsFeatureResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*twirpFeatures.CheckActorsFeatureResponse)
	return args0, args.Error(1)
}

// CheckActorFeatures mocks the monolith-twirp FeaturesAPI.CheckActorFeatures method.
func (m *MockFeatureFlagsAPI) CheckActorFeatures(ctx context.Context, request *twirpFeatures.CheckActorFeaturesRequest) (*twirpFeatures.CheckActorFeaturesResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*twirpFeatures.CheckActorFeaturesResponse)
	return args0, args.Error(1)
}

// CheckGlobalFeature mocks the monolith-twirp FeaturesAPI.CheckGlobalFeature method.
func (m *MockFeatureFlagsAPI) CheckGlobalFeature(ctx context.Context, request *twirpFeatures.CheckGlobalFeatureRequest) (*twirpFeatures.CheckGlobalFeatureResponse, error) {
	args := m.Called(ctx, request)
	args0, _ := args.Get(0).(*twirpFeatures.CheckGlobalFeatureResponse)
	return args0, args.Error(1)
}

// MockAqueductClient mocks the aqueduct.Client for testing.
type MockAqueductClient struct {
	mock.Mock
	aqueduct.Client
}

// Send mocks the aqueduct.Client Send method.
func (m *MockAqueductClient) Send(ctx context.Context, j aqueduct.Job, opts ...aqueduct.SendOption) (string, error) {
	args := m.Called(ctx, j, opts)
	return args.String(0), args.Error(1)
}

// SendBatch mocks the aqueduct.Client SendBatch method.
func (m *MockAqueductClient) SendBatch(ctx context.Context, batch []aqueduct.BatchItem) (*aqueduct.SendBatchResult, error) {
	args := m.Called(ctx, batch)
	result, ok := args.Get(0).(*aqueduct.SendBatchResult)
	if !ok && args.Get(0) != nil {
		return nil, fmt.Errorf("expected *aqueduct.SendBatchResult but got %T", args.Get(0))
	}
	return result, args.Error(1)
}

// MockHydroPublisher is a mock implementation of the HydroPublisher interface.
type MockHydroPublisher struct {
	mock.Mock
}

// Publish is the mock implementation of the HydroPublisher's Publish method.
func (m *MockHydroPublisher) Publish(msg proto.Message, opts ...hydro.PublishOption) error {
	args := m.Called(msg, opts)
	return args.Error(0)
}
