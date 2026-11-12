// Package cosmosdb implements a JobsStore using Azure Cosmos DB as the backend.
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
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/sweagentd/internal/config"
	cosmosbase "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	"github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

// MaxOperationsInTransactionalBatch defines the maximum number of operations
// allowed in a single transactional batch.
//
// https://learn.microsoft.com/en-us/azure/cosmos-db/concepts-limits#per-request-limits
const MaxOperationsInTransactionalBatch = 100

var errMultipleItemsFoundForQuery = errors.New("more than one item found for query")

// CosmosJobsStore is a Cosmos DB implementation of the JobsStore interface.
type CosmosJobsStore struct {
	assignments *azcosmos.ContainerClient
	jobs        *azcosmos.ContainerClient
	commands    *azcosmos.ContainerClient
	progress    *azcosmos.ContainerClient
	obsv        observability.Exporters
}

// Ensure that CosmosJobStore implements JobStore
var _ store.JobsStore = &CosmosJobsStore{}

func repoPk(owner, repo int64) azcosmos.PartitionKey {
	return azcosmos.NewPartitionKey().AppendNumber(float64(owner)).AppendNumber(float64(repo))
}

func pk(owner, repo int64, id string) azcosmos.PartitionKey {
	return repoPk(owner, repo).AppendString(id)
}

func jobPK(assignmentID, jobID string) azcosmos.PartitionKey {
	return azcosmos.NewPartitionKey().AppendString(assignmentID).AppendString(jobID)
}

// CosmosJobStoreOpts holds configuration options for connecting to a Cosmos DB instance.
type CosmosJobStoreOpts struct {
	Endpoint                    string
	ConnectionString            string
	DatabaseID                  string
	JobsContainerID             string
	AssignmentsContainerID      string
	CommandsContainerID         string
	ProgressContainerID         string
	IntervalTriggersContainerID string // Used only by EnsureCosmosStructure (emulator/dev setup).
	SPNTenantID                 string
	SPNClientID                 string

	// Agent config containers (used by EnsureCosmosStructure for emulator setup)
	RepositoryAgentsContainerID   string
	OrganizationAgentsContainerID string
	EnterpriseAgentsContainerID   string
}

// NewCosmosJobStore creates a new CosmosJobStore with the given options.
func NewCosmosJobStore(obsv observability.Exporters, opts *CosmosJobStoreOpts) (*CosmosJobsStore, error) {
	cosmos, err := cosmosbase.NewCosmosClient(&cosmosbase.Opts{
		ConnectionString:         opts.ConnectionString,
		Endpoint:                 opts.Endpoint,
		AzureCosmosDBSPNTenantID: opts.SPNTenantID,
		AzureCosmosDBSPNClientID: opts.SPNClientID,
		Obsv:                     obsv,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to create Cosmos client: %w", err)
	}

	assignments, err := cosmos.NewContainer(opts.DatabaseID, opts.AssignmentsContainerID)
	if err != nil {
		return nil, err
	}

	jobs, err := cosmos.NewContainer(opts.DatabaseID, opts.JobsContainerID)
	if err != nil {
		return nil, err
	}

	commands, err := cosmos.NewContainer(opts.DatabaseID, opts.CommandsContainerID)
	if err != nil {
		return nil, err
	}

	progress, err := cosmos.NewContainer(opts.DatabaseID, opts.ProgressContainerID)
	if err != nil {
		return nil, err
	}

	return &CosmosJobsStore{
		assignments: assignments,
		jobs:        jobs,
		commands:    commands,
		progress:    progress,
		obsv:        obsv,
	}, nil
}

// TryCosmosEmulator attempts to connect to a local Cosmos DB emulator for development
func TryCosmosEmulator(obsv observability.Exporters, cfg *config.Config) (store.JobsStore, error) {
	if !cfg.IsDevelopment() {
		return nil, goerrors.New("cosmos emulator can only be used in development mode")
	}

	// Use emulator configuration from cfg (loaded from .env.cosmos-dev)
	emulatorOpts := &CosmosJobStoreOpts{
		ConnectionString:              cfg.AzureCosmosDBConnectionString,
		DatabaseID:                    cfg.AzureCosmosDBDatabase,
		AssignmentsContainerID:        cfg.AzureCosmosDBContainerAssignment,
		JobsContainerID:               cfg.AzureCosmosDBContainerJobs,
		CommandsContainerID:           cfg.AzureCosmosDBContainerCommands,
		ProgressContainerID:           cfg.AzureCosmosDBContainerProgress,
		RepositoryAgentsContainerID:   cfg.AzureCosmosDBContainerRepositoryAgents,
		OrganizationAgentsContainerID: cfg.AzureCosmosDBContainerOrganizationAgents,
		EnterpriseAgentsContainerID:   cfg.AzureCosmosDBContainerEnterpriseAgents,
		IntervalTriggersContainerID:   cfg.AzureCosmosDBContainerIntervalTriggers,
	}

	// Ensure the database and containers exist
	err := EnsureCosmosStructure(emulatorOpts)
	if err != nil {
		return nil, goerrors.Errorf("failed to ensure Cosmos DB structure: %w", err)
	}

	return NewCosmosJobStore(obsv, emulatorOpts)
}

// EnsureCosmosStructure creates the Cosmos DB database and containers if they
// do not already exist. This is purely for setup and testing purposes, and
// **should not be used in production**.
func EnsureCosmosStructure(opts *CosmosJobStoreOpts) error {
	ctx := context.Background()

	// Create Cosmos client for setup
	var err error

	if opts.ConnectionString == "" {
		return goerrors.New("no Cosmos DB connection configuration found")
	}

	// Create Cosmos client for setup using the provided connection string
	client, err := cosmosbase.NewCosmosClient(&cosmosbase.Opts{
		ConnectionString: opts.ConnectionString,
	})
	if err != nil {
		return goerrors.Errorf("failed to create Cosmos client: %w", err)
	}

	// Create database if it doesn't exist
	fmt.Printf("Ensuring database '%s' exists...\n", opts.DatabaseID)
	_, err = client.CreateDatabase(ctx, azcosmos.DatabaseProperties{
		ID: opts.DatabaseID,
	}, nil)
	if err != nil {
		// Check if it's a conflict error (database already exists)
		var respErr *azcore.ResponseError
		if !errors.As(err, &respErr) || respErr.StatusCode != http.StatusConflict {
			return goerrors.Errorf("failed to create database: %w", err)
		}
		fmt.Printf("Database '%s' already exists\n", opts.DatabaseID)
	} else {
		fmt.Printf("Database '%s' created successfully\n", opts.DatabaseID)
	}

	// Get database reference
	database, err := client.NewDatabase(opts.DatabaseID)
	if err != nil {
		return goerrors.Errorf("failed to get database reference: %w", err)
	}

	// Create containers with proper partition keys
	// This needs to match the partition keys defined in our production setup

	// Multi-hash partition key containers (jobs infrastructure)
	multiHashContainers := map[string][]string{
		opts.AssignmentsContainerID: {"/owner_id", "/repo_id", "/id"},
		opts.JobsContainerID:        {"/owner_id", "/repo_id", "/id"},
		opts.CommandsContainerID:    {"/assignment_id", "/job_id"},
		opts.ProgressContainerID:    {"/assignment_id", "/job_id"},
	}

	for containerName, partitionKeyPaths := range multiHashContainers {
		err = ensureContainer(ctx, database, containerName, partitionKeyPaths, azcosmos.PartitionKeyKindMultiHash)
		if err != nil {
			return err
		}
	}

	// Single partition key containers (agent config stores)
	singleKeyContainers := map[string]string{
		opts.RepositoryAgentsContainerID:   "/scope_id",
		opts.OrganizationAgentsContainerID: "/scope_id",
		opts.EnterpriseAgentsContainerID:   "/scope_id",
		opts.IntervalTriggersContainerID:   "/scope_id",
	}

	for containerName, partitionKeyPath := range singleKeyContainers {
		if containerName == "" {
			continue
		}
		err = ensureContainer(ctx, database, containerName, []string{partitionKeyPath}, azcosmos.PartitionKeyKindHash)
		if err != nil {
			return err
		}
	}

	fmt.Println("Cosmos DB structure setup completed successfully!")
	return nil
}

// ensureContainer creates a container if it doesn't already exist.
func ensureContainer(ctx context.Context, database *azcosmos.DatabaseClient, name string, paths []string, kind azcosmos.PartitionKeyKind) error {
	fmt.Printf("Ensuring container '%s' exists...\n", name)

	_, err := database.CreateContainer(ctx, azcosmos.ContainerProperties{
		ID: name,
		PartitionKeyDefinition: azcosmos.PartitionKeyDefinition{
			Paths:   paths,
			Kind:    kind,
			Version: 2,
		},
	}, nil)

	if err != nil {
		var respErr *azcore.ResponseError
		if !errors.As(err, &respErr) || respErr.StatusCode != http.StatusConflict {
			return goerrors.Errorf("failed to create container '%s': %w", name, err)
		}
		fmt.Printf("Container '%s' already exists\n", name)
	} else {
		fmt.Printf("Container '%s' created successfully\n", name)
	}

	return nil
}

// CreateAssignment creates a new assignment in the database.
func (s *CosmosJobsStore) CreateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.CreateAssignment")
	defer span.End()

	pk := pk(assignment.OwnerID, assignment.RepoID, assignment.ID)

	if assignment.CreatedAt == 0 {
		assignment.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(assignment)
	if err != nil {
		return nil, err
	}

	response, err := s.assignments.CreateItem(ctx, pk, marshalled, nil)
	if err != nil {
		return nil, err
	}

	err = json.Unmarshal(response.Value, &assignment)
	if err != nil {
		return nil, err
	}

	return assignment, nil
}

// GetAssignment retrieves an assignment by its ID.
func (s *CosmosJobsStore) GetAssignment(ctx context.Context, owner, repo int64, id string) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetAssignment")
	defer span.End()

	pk := pk(owner, repo, id)

	response, err := s.assignments.ReadItem(ctx, pk, id, nil)
	if err != nil {
		var respErr *azcore.ResponseError
		if errors.As(err, &respErr) && respErr.StatusCode == http.StatusNotFound {
			return nil, store.NewErrAssignmentNotFound()
		}
		return nil, err
	}

	var item *jobs.Assignment
	err = json.Unmarshal(response.Value, &item)
	if err != nil {
		return nil, err
	}

	return item, nil
}

// GetAssignments retrieves all assignments for a given owner and repository.
func (s *CosmosJobsStore) GetAssignments(ctx context.Context, owner, repo int64) ([]*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetAssignments")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id"
	pager := s.assignments.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.Assignment](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get assignments: %w", err)
	}
	return items, nil
}

// UpdateAssignment updates an existing assignment in the database.
func (s *CosmosJobsStore) UpdateAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpdateAssignment")
	defer span.End()

	pk := pk(assignment.OwnerID, assignment.RepoID, assignment.ID)

	marshalled, err := json.Marshal(assignment)
	if err != nil {
		return nil, err
	}

	response, err := s.assignments.UpsertItem(ctx, pk, marshalled, nil)
	if err != nil {
		return nil, err
	}

	err = json.Unmarshal(response.Value, &assignment)
	if err != nil {
		return nil, err
	}

	return assignment, nil
}

// UpsertAssignment creates or updates an assignment in the database.
func (s *CosmosJobsStore) UpsertAssignment(ctx context.Context, assignment *jobs.Assignment) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpsertAssignment")
	defer span.End()

	pk := pk(assignment.OwnerID, assignment.RepoID, assignment.ID)

	if assignment.CreatedAt == 0 {
		assignment.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(assignment)
	if err != nil {
		return nil, err
	}

	opts := &azcosmos.ItemOptions{EnableContentResponseOnWrite: true}
	if assignment.ETag != nil {
		opts.IfMatchEtag = assignment.ETag
	}

	response, err := s.assignments.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return nil, store.NewErrPreconditionFailedOnUpdate()
		}
		return nil, err
	}

	err = json.Unmarshal(response.Value, &assignment)
	if err != nil {
		return nil, err
	}

	return assignment, nil
}

// PatchAssignment patches specific fields on the assignment in the database.
func (s *CosmosJobsStore) PatchAssignment(ctx context.Context, assignment *jobs.Assignment, patch store.AssignmentPatch, opts ...store.PatchAssignmentOption) error {
	options := &store.PatchAssignmentOptionsAccumulator{}
	for _, o := range opts {
		o(options)
	}

	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.PatchAssignment")
	defer span.End()

	pk := pk(assignment.OwnerID, assignment.RepoID, assignment.ID)
	patchOps := azcosmos.PatchOperations{}

	if patch.PullRequestID != nil {
		patchOps.AppendAdd("/pull_request_id", *patch.PullRequestID)
	}
	if patch.PullRequestNumber != nil {
		patchOps.AppendAdd("/pull_request_number", *patch.PullRequestNumber)
	}
	if patch.Experiments != nil && patch.Experiments.AssignmentContext != "" {
		patchOps.AppendAdd("/experiments", *patch.Experiments)
	}

	itemOptions := &azcosmos.ItemOptions{
		EnableContentResponseOnWrite: true,
	}

	if condition := store.BuildCosmosCondition(options.FieldConditions); condition != "" {
		patchOps.SetCondition(condition)
	} else if !options.DisableEtagCheck {
		itemOptions.IfMatchEtag = assignment.ETag
	}

	response, err := s.assignments.PatchItem(ctx, pk, assignment.ID, patchOps, itemOptions)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return store.NewErrPreconditionFailedOnUpdate()
		}
		return err
	}

	err = json.Unmarshal(response.Value, &assignment)
	if err != nil {
		return err
	}

	return nil
}

// DeleteAssignment deletes an assignment from the database.
func (s *CosmosJobsStore) DeleteAssignment(ctx context.Context, owner, repo int64, id string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.DeleteAssignment")
	defer span.End()

	pk := pk(owner, repo, id)

	_, err := s.assignments.DeleteItem(ctx, pk, id, nil)
	if err != nil {
		return err
	}

	return nil
}

func getIssueQuery(base string, owner, repo int64, id *int64, number *int) (string, azcosmos.QueryOptions, error) {
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
		},
	}
	if id == nil && number == nil {
		return "", opt, goerrors.New("either id or number must be provided")
	}

	// construct a query that checks the org/repo specific partition
	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND ("
	if id != nil {
		opt.QueryParameters = append(opt.QueryParameters, azcosmos.QueryParameter{Name: "@issue_id", Value: id})
		query += "c." + base + "_id = @issue_id"
	}
	if number != nil {
		opt.QueryParameters = append(opt.QueryParameters, azcosmos.QueryParameter{Name: "@issue_number", Value: number})
		if id != nil {
			query += " OR "
		}
		query += "c." + base + "_number = @issue_number"
	}
	query += ")"

	return query, opt, nil
}

// GetAssignmentForPR returns the assignment for the pull request id and/or number.
func (s *CosmosJobsStore) GetAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetAssignmentForPR")
	defer span.End()

	query, opt, err := getIssueQuery("pull_request", owner, repo, id, number)
	if err != nil {
		return nil, err
	}

	pager := s.assignments.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	item, err := getSingleItemFromPager[jobs.Assignment](ctx, pager)
	if err != nil {
		if errors.Is(err, errMultipleItemsFoundForQuery) {
			return nil, goerrors.New("multiple assignments found for PR")
		}
		return nil, goerrors.Errorf("failed to get assignment for PR: %w", err)
	}

	return item, nil
}

// GetLatestAssignmentForPR returns the most recently created assignment for the pull request
// id and/or number. When multiple assignments match, a warning is logged and the assignment
// with the latest CreatedAt timestamp is returned.
func (s *CosmosJobsStore) GetLatestAssignmentForPR(ctx context.Context, owner, repo int64, id *int64, number *int) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetLatestAssignmentForPR")
	defer span.End()

	query, opt, err := getIssueQuery("pull_request", owner, repo, id, number)
	if err != nil {
		return nil, err
	}

	pager := s.assignments.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.Assignment](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get latest assignment for PR: %w", err)
	}

	if len(items) == 0 {
		return nil, nil
	}

	if len(items) > 1 {
		s.obsv.LoggerWithTelemetry(ctx).Warn(fmt.Sprintf("multiple assignments (%d) found for PR, returning latest", len(items)))
	}

	// Sort client-side since ORDER BY is not supported in cross-partition queries.
	latest := items[0]
	for _, item := range items[1:] {
		if item.CreatedAt > latest.CreatedAt {
			latest = item
		}
	}

	return latest, nil
}

func getResourceQuery(owner, repo int64, resource jobs.AssignmentResource) (string, azcosmos.QueryOptions, error) {
	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@resource_id", Value: resource.ID},
		},
	}

	if resource.ID == "" {
		return "", opt, goerrors.New("resource ID must be provided")
	}

	// construct a query that checks the org/repo specific partition and the resource ID
	query := "SELECT VALUE c FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND EXISTS(SELECT VALUE r FROM r IN c.resources WHERE r.id = @resource_id"

	if resource.Type != "" {
		opt.QueryParameters = append(opt.QueryParameters, azcosmos.QueryParameter{Name: "@resource_type", Value: resource.Type})
		query += " AND r.type = @resource_type"
	}
	query += ")"
	return query, opt, nil
}

// GetAssignmentForResource retrieves the assignment associated with a specific resource.
func (s *CosmosJobsStore) GetAssignmentForResource(ctx context.Context, owner, repo int64, resource jobs.AssignmentResource) (*jobs.Assignment, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetAssignmentForResource")
	defer span.End()

	query, opt, err := getResourceQuery(owner, repo, resource)
	if err != nil {
		return nil, err
	}

	pager := s.assignments.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	item, err := getSingleItemFromPager[jobs.Assignment](ctx, pager)
	if err != nil {
		if errors.Is(err, errMultipleItemsFoundForQuery) {
			return nil, store.NewErrMultipleAssignmentsForResource()
		}
		return nil, goerrors.Errorf("failed to get assignment for resource: %w", err)
	}

	return item, nil
}

// DetachAssignmentResource adds the given resource to the assignment's detached
// resources list and removes it from the active resources list.
func (s *CosmosJobsStore) DetachAssignmentResource(ctx context.Context, assignment *jobs.Assignment, resource jobs.AssignmentResource) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.DetachAssignmentResource")
	defer span.End()

	assignment, err := s.GetAssignment(ctx, assignment.OwnerID, assignment.RepoID, assignment.ID)
	if err != nil {
		return err
	}

	remove := -1
	for i, r := range assignment.Resources {
		if r.ID == resource.ID && r.Type == resource.Type {
			remove = i
			assignment.DetachedResources = append(assignment.DetachedResources, r)
			break
		}
	}

	if remove == -1 {
		for _, r := range assignment.DetachedResources {
			if r.ID == resource.ID && r.Type == resource.Type {
				return nil // already detached
			}
		}
		return goerrors.Errorf("resource %s not found in assignment %s", resource.ID, assignment.ID)
	}

	assignment.Resources = slices.Delete(assignment.Resources, remove, remove+1)
	_, err = s.UpdateAssignment(ctx, assignment)

	if err != nil {
		return err
	}

	return nil
}

// DetachAssignmentResources detaches all resources from the given assignment.
func (s *CosmosJobsStore) DetachAssignmentResources(ctx context.Context, assignment *jobs.Assignment) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.DetachAssignmentResources")
	defer span.End()

	assignment, err := s.GetAssignment(ctx, assignment.OwnerID, assignment.RepoID, assignment.ID)
	if err != nil {
		return err
	}

	assignment.DetachedResources = append(assignment.DetachedResources, assignment.Resources...)
	assignment.Resources = []jobs.AssignmentResource{}

	_, err = s.UpdateAssignment(ctx, assignment)
	if err != nil {
		return err
	}

	return nil
}

// GetJobsForAssignment retrieves all jobs associated with a specific assignment.
func (s *CosmosJobsStore) GetJobsForAssignment(ctx context.Context, assignment *jobs.Assignment) ([]*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobsForAssignment")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: assignment.OwnerID},
			{Name: "@repo_id", Value: assignment.RepoID},
			{Name: "@assignment_id", Value: assignment.ID},
		},
	}
	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.assignment_id = @assignment_id"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.Job](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}

	return items, nil
}

// GetJobSummariesForAssignmentID retrieves job summaries for a specific assignment ID.
func (s *CosmosJobsStore) GetJobSummariesForAssignmentID(ctx context.Context, owner, repo int64, assignmentID string) ([]*jobs.JobSummary, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobSummariesForAssignmentID")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@assignment_id", Value: assignmentID},
		},
	}
	query := fmt.Sprintf("SELECT %s FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.assignment_id = @assignment_id", jobSummaryFieldsSelect("c"))
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.JobSummary](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for assignment: %w", err)
	}

	return items, nil
}

// CreateJob creates a new job in the database.
func (s *CosmosJobsStore) CreateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.CreateJob")
	defer span.End()

	pk := pk(job.OwnerID, job.RepoID, job.ID)

	if job.CreatedAt == 0 {
		job.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(job)
	if err != nil {
		return nil, err
	}

	response, err := s.jobs.CreateItem(ctx, pk, marshalled, nil)
	if err != nil {
		return nil, err
	}

	err = json.Unmarshal(response.Value, &job)
	if err != nil {
		return nil, err
	}

	return job, nil
}

// GetJob retrieves a job by its ID.
func (s *CosmosJobsStore) GetJob(ctx context.Context, owner, repo int64, id string) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJob")
	defer span.End()

	pk := pk(owner, repo, id)

	response, err := s.jobs.ReadItem(ctx, pk, id, nil)
	if err != nil {
		return nil, err
	}

	var item *jobs.Job
	err = json.Unmarshal(response.Value, &item)
	if err != nil {
		return nil, err
	}

	return item, nil
}

// GetJobForComputeID retrieves a job by its compute ID.
func (s *CosmosJobsStore) GetJobForComputeID(ctx context.Context, owner, repo int64, computeID string) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobForComputeID")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@compute_id", Value: computeID},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.compute_id = @compute_id"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	item, err := getSingleItemFromPager[jobs.Job](ctx, pager)
	if err != nil {
		if errors.Is(err, errMultipleItemsFoundForQuery) {
			return nil, goerrors.New("multiple jobs found for compute ID")
		}
		return nil, goerrors.Errorf("failed to get job for compute ID: %w", err)
	}

	return item, nil
}

// GetJobForSessionID retrieves a job by its session ID.
func (s *CosmosJobsStore) GetJobForSessionID(ctx context.Context, owner, repo int64, sessionID string) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobForSessionID")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@session_id", Value: sessionID},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.session_id = @session_id"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	item, err := getSingleItemFromPager[jobs.Job](ctx, pager)
	if err != nil {
		if errors.Is(err, errMultipleItemsFoundForQuery) {
			return nil, goerrors.New("multiple jobs found for session ID")
		}
		return nil, goerrors.Errorf("failed to get job for session ID: %w", err)
	}

	return item, nil
}

// GetJobForActorOnboarding retrieves a job for actor onboarding by owner, repo, and actor ID.
func (s *CosmosJobsStore) GetJobForActorOnboarding(ctx context.Context, owner, repo, actor int64) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobForActorOnboarding")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@actor_id", Value: actor},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.actor_id = @actor_id AND c.onboarding_comment_id != 0"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	item, err := getSingleItemFromPager[jobs.Job](ctx, pager)
	if err != nil {
		if errors.Is(err, errMultipleItemsFoundForQuery) {
			return nil, goerrors.New("multiple jobs found for actor onboarding")
		}
		return nil, goerrors.Errorf("failed to get job for actor onboarding: %w", err)
	}

	return item, nil
}

// ListJobsForPullRequestNumber lists all jobs associated with a specific pull request number.
func (s *CosmosJobsStore) ListJobsForPullRequestNumber(ctx context.Context, owner, repo int64, prNumber int) ([]*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.ListJobsForPullRequestNumber")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@pull_request_number", Value: prNumber},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.pull_request_number = @pull_request_number"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.Job](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs for pull request number: %w", err)
	}

	return items, nil
}

// CountJobsForBranchAndEventType returns the number of jobs for a given repo,
// branch, and event type.
func (s *CosmosJobsStore) CountJobsForBranchAndEventType(ctx context.Context, owner, repo int64, branch string, eventType jobs.EventType) (int, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.CountJobsForBranchAndEventType")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
			{Name: "@branch_name", Value: branch},
			{Name: "@event_type", Value: string(eventType)},
		},
	}

	query := "SELECT c.id FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id AND c.branch_name = @branch_name AND c.event_type = @event_type"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	count, err := countAllItemsFromPager(ctx, pager)
	if err != nil {
		return 0, goerrors.Errorf("failed to count jobs for branch and event type: %w", err)
	}

	return count, nil
}

// jobSummaryFieldsSelect returns a string that represents the fields of a job summary.
// Example: "c.id, c.repo_id, c.owner_id, c.status, ..."
func jobSummaryFieldsSelect(alias string) string {
	return selectFields(jobs.JobSummaryFields, alias)
}

// GetRunningJobCountForActor returns the count of running jobs for a specific
// actor within a given time window.
func (s *CosmosJobsStore) GetRunningJobCountForActor(ctx context.Context, actor int64, window time.Duration) (int, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetRunningJobCountForActor")
	defer span.End()

	minCreatedAt := time.Now().Add(-window).Unix()
	if window <= 0 {
		d := 24 * time.Hour // default to 24 hours
		minCreatedAt = time.Now().Add(-d).Unix()
	}

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@actor_id", Value: actor},
			{Name: "@status", Value: string(jobs.JobStatusRunning)},
			{Name: "@min_created_at", Value: minCreatedAt},
		},
	}

	query := fmt.Sprintf("SELECT %s FROM c WHERE c.actor_id = @actor_id AND c.status = @status AND c.created_at >= @min_created_at", jobSummaryFieldsSelect("c"))
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := countAllItemsFromPager(ctx, pager)
	if err != nil {
		return 0, goerrors.Errorf("failed to get running jobs for actor: %w", err)
	}

	return items, nil
}

// GetJobCountByStatusForActor returns the count of jobs by status for a specific
// actor within a given time window. If excludeAgentIDs is non-empty, jobs
// belonging to those agent IDs are excluded from the counts.
func (s *CosmosJobsStore) GetJobCountByStatusForActor(ctx context.Context, actor int64, window time.Duration, excludeAgentIDs []int64) (sweagentd.JobCounts, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobCountByStatusForActor")
	defer span.End()

	minCreatedAt := time.Now().Add(-window).Unix()
	if window <= 0 {
		d := 2 * time.Hour // default to 2 hours, but this shouldn't be relied on
		minCreatedAt = time.Now().Add(-d).Unix()
	}

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@actor_id", Value: actor},
			{Name: "@status_running", Value: string(jobs.JobStatusRunning)},
			{Name: "@status_queued", Value: string(jobs.JobStatusQueued)},
			{Name: "@min_created_at", Value: minCreatedAt},
		},
	}

	// When excluding specific agents, also project agent_id so we can filter in
	// Go (Cosmos DB does not support parameterized NOT IN with arrays). When
	// nothing is excluded, keep the narrower projection for efficiency.
	selectClause := jobSummaryFieldsSelect("c")
	if len(excludeAgentIDs) > 0 {
		selectClause += ", c.agent_id"
	}
	query := fmt.Sprintf("SELECT %s FROM c WHERE c.actor_id = @actor_id AND (c.status = @status_running OR c.status = @status_queued) AND c.created_at >= @min_created_at", selectClause)
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	excluded := make(map[int64]bool, len(excludeAgentIDs))
	for _, id := range excludeAgentIDs {
		excluded[id] = true
	}

	counts := sweagentd.JobCounts{}
	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			return counts, err
		}
		for _, item := range response.Items {
			var doc struct {
				jobs.JobSummary

				AgentID int64 `json:"agent_id"`
			}
			err = json.Unmarshal(item, &doc)
			if err != nil {
				return counts, err
			}
			if len(excluded) > 0 && excluded[doc.AgentID] {
				continue
			}
			switch doc.Status {
			case jobs.JobStatusRunning:
				counts.Running++
			case jobs.JobStatusQueued:
				counts.Queued++
			default:
				// ignore other statuses
			}
		}
	}

	return counts, nil
}

// GetJobs retrieves all jobs for a given owner and repository.
func (s *CosmosJobsStore) GetJobs(ctx context.Context, owner, repo int64) ([]*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetJobs")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@owner_id", Value: owner},
			{Name: "@repo_id", Value: repo},
		},
	}

	query := "SELECT * FROM c WHERE c.owner_id = @owner_id AND c.repo_id = @repo_id"
	pager := s.jobs.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[jobs.Job](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get jobs: %w", err)
	}

	return items, nil
}

// UpdateJob updates an existing job in the database.
func (s *CosmosJobsStore) UpdateJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpdateJob")
	defer span.End()

	pk := pk(job.OwnerID, job.RepoID, job.ID)

	marshalled, err := json.Marshal(job)
	if err != nil {
		return nil, err
	}

	opts := &azcosmos.ItemOptions{EnableContentResponseOnWrite: true}
	if job.ETag != nil {
		opts.IfMatchEtag = job.ETag
	}

	response, err := s.jobs.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return nil, store.NewErrPreconditionFailedOnUpdate()
		}
		return nil, err
	}

	err = json.Unmarshal(response.Value, &job)
	if err != nil {
		return nil, err
	}

	return job, nil
}

// UpsertJob creates or updates a job in the database.
func (s *CosmosJobsStore) UpsertJob(ctx context.Context, job *jobs.Job) (*jobs.Job, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpsertJob")
	defer span.End()

	pk := pk(job.OwnerID, job.RepoID, job.ID)

	if job.CreatedAt == 0 {
		job.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(job)
	if err != nil {
		return nil, err
	}

	opts := &azcosmos.ItemOptions{EnableContentResponseOnWrite: true}
	if job.ETag != nil {
		opts.IfMatchEtag = job.ETag
	}

	response, err := s.jobs.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return nil, store.NewErrPreconditionFailedOnUpdate()
		}
		return nil, err
	}

	err = json.Unmarshal(response.Value, &job)
	if err != nil {
		return nil, err
	}

	return job, nil
}

// DeleteJob deletes a job from the database.
func (s *CosmosJobsStore) DeleteJob(ctx context.Context, owner, repo int64, id string) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.DeleteJob")
	defer span.End()

	pk := pk(owner, repo, id)

	_, err := s.jobs.DeleteItem(ctx, pk, id, nil)
	if err != nil {
		return err
	}

	return nil
}

// PatchJob applies a partial update to a job using Cosmos DB's PatchItem functionality.
// Only fields set in the JobPatch will be updated.
// It has a *very important* side effect to take note of, which is that it will
// overwrite any fields not included in the patch with the database's stored value.
// For example, if you have a Job with a non-empty branch name field, and you patch
// the Status field only, the branch name field will be set to what's in the db, not what's
// in memory.
//
// This is because we override the entire pointer object with the patched version.
//
// TODO(josebalius): We really need to fix this.
func (s *CosmosJobsStore) PatchJob(ctx context.Context, job *jobs.Job, patch store.JobPatch, opts ...store.PatchJobOption) error {
	options := &store.PatchJobOptionsAccumulator{}
	for _, o := range opts {
		o(options)
	}

	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.PatchJob")
	defer span.End()

	pk := pk(job.OwnerID, job.RepoID, job.ID)
	patchOps := azcosmos.PatchOperations{}

	if patch.Status != nil {
		patchOps.AppendAdd("/status", *patch.Status)
	}
	if patch.ComputeID != nil {
		patchOps.AppendAdd("/compute_id", *patch.ComputeID)
	}
	if patch.CompletedAt != nil {
		patchOps.AppendAdd("/completed_at", *patch.CompletedAt)
	}
	if patch.StartedAt != nil {
		patchOps.AppendAdd("/started_at", *patch.StartedAt)
	}
	if patch.RunningAt != nil {
		patchOps.AppendAdd("/running_at", *patch.RunningAt)
	}
	if patch.BranchName != nil {
		patchOps.AppendAdd("/branch_name", *patch.BranchName)
	}
	if patch.PullRequestID != nil {
		patchOps.AppendAdd("/pull_request_id", *patch.PullRequestID)
	}
	if patch.PullRequestNumber != nil {
		patchOps.AppendAdd("/pull_request_number", *patch.PullRequestNumber)
	}
	if patch.ReplyCommentID != nil {
		patchOps.AppendAdd("/reply_comment_id", *patch.ReplyCommentID)
	}
	if patch.OnboardingCommentID != nil {
		patchOps.AppendAdd("/onboarding_comment_id", *patch.OnboardingCommentID)
	}
	if patch.SessionID != nil {
		patchOps.AppendAdd("/session_id", *patch.SessionID)
	}
	if patch.QueuedAt != nil {
		patchOps.AppendAdd("/queued_at", *patch.QueuedAt)
	}
	if patch.Error != nil {
		patchOps.AppendAdd("/error", *patch.Error)
	}
	if patch.Experiments != nil && patch.Experiments.AssignmentContext != "" {
		patchOps.AppendAdd("/experiments", *patch.Experiments)
	}
	if patch.Model != nil {
		patchOps.AppendAdd("/model", *patch.Model)
	}
	if patch.CustomAgent != nil {
		patchOps.AppendAdd("/custom_agent", *patch.CustomAgent)
	}

	itemOptions := &azcosmos.ItemOptions{
		EnableContentResponseOnWrite: true,
	}

	if condition := store.BuildCosmosCondition(options.FieldConditions); condition != "" {
		patchOps.SetCondition(condition)
	} else if !options.DisableEtagCheck {
		itemOptions.IfMatchEtag = job.ETag
	}

	response, err := s.jobs.PatchItem(ctx, pk, job.ID, patchOps, itemOptions)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return store.NewErrPreconditionFailedOnUpdate()
		}
		return err
	}

	err = json.Unmarshal(response.Value, &job)
	if err != nil {
		return err
	}

	return nil
}

// CreateCommand creates a new command in the database.
func (s *CosmosJobsStore) CreateCommand(ctx context.Context, command *command.Command) (*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.CreateCommand")
	defer span.End()

	pk := jobPK(command.AssignmentID, command.JobID)

	if command.CreatedAt == 0 {
		command.CreatedAt = time.Now().Unix()
	}

	marshalled, err := json.Marshal(command)
	if err != nil {
		return nil, err
	}

	response, err := s.commands.CreateItem(ctx, pk, marshalled, nil)
	if err != nil {
		return nil, err
	}

	err = json.Unmarshal(response.Value, &command)
	if err != nil {
		return nil, err
	}

	return command, nil
}

// GetCommand retrieves a command by its ID.
func (s *CosmosJobsStore) GetCommand(ctx context.Context, assignmentID, jobID, id string) (*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetCommand")
	defer span.End()

	pk := jobPK(assignmentID, jobID)

	response, err := s.commands.ReadItem(ctx, pk, id, nil)
	if err != nil {
		return nil, err
	}

	var item *command.Command
	err = json.Unmarshal(response.Value, &item)
	if err != nil {
		return nil, err
	}

	return item, nil
}

// GetCommands retrieves all commands for a given assignment and job.
func (s *CosmosJobsStore) GetCommands(ctx context.Context, assignmentID, jobID string) ([]*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetCommands")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@assignment_id", Value: assignmentID},
			{Name: "@job_id", Value: jobID},
		},
	}

	query := "SELECT * FROM c WHERE c.assignment_id = @assignment_id AND c.job_id = @job_id"
	pager := s.commands.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[command.Command](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get commands: %w", err)
	}

	return items, nil
}

// GetCommandsWithStatus retrieves all commands for a given assignment, job, and status.
func (s *CosmosJobsStore) GetCommandsWithStatus(ctx context.Context, assignmentID, jobID string, status command.Status) ([]*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.GetCommandsWithStatus")
	defer span.End()

	opt := azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@assignment_id", Value: assignmentID},
			{Name: "@job_id", Value: jobID},
			{Name: "@status", Value: string(status)},
		},
	}

	query := "SELECT * FROM c WHERE c.assignment_id = @assignment_id AND c.job_id = @job_id AND c.status = @status"
	pager := s.commands.NewQueryItemsPager(query, azcosmos.NewPartitionKey(), &opt)

	items, err := getAllItemsFromPager[command.Command](ctx, pager)
	if err != nil {
		return nil, goerrors.Errorf("failed to get commands: %w", err)
	}

	return items, nil
}

// UpdateCommand updates an existing command in the database.
func (s *CosmosJobsStore) UpdateCommand(ctx context.Context, command *command.Command) (*command.Command, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.UpdateCommand")
	defer span.End()

	pk := jobPK(command.AssignmentID, command.JobID)

	marshalled, err := json.Marshal(command)
	if err != nil {
		return nil, err
	}

	opts := &azcosmos.ItemOptions{EnableContentResponseOnWrite: true}
	if command.ETag != nil {
		opts.IfMatchEtag = command.ETag
	}

	response, err := s.commands.UpsertItem(ctx, pk, marshalled, opts)
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return nil, store.NewErrPreconditionFailedOnUpdate()
		}
		return nil, err
	}

	err = json.Unmarshal(response.Value, &command)
	if err != nil {
		return nil, err
	}

	return command, nil
}

// PatchCommand applies a partial update to a command in the database.
func (s *CosmosJobsStore) PatchCommand(ctx context.Context, command *command.Command, patch store.CommandPatch) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.PatchCommand")
	defer span.End()

	pk := jobPK(command.AssignmentID, command.JobID)
	patchOps := azcosmos.PatchOperations{}

	if patch.Status != nil {
		patchOps.AppendAdd("/status", *patch.Status)
	}
	if patch.DeliveredAt != nil {
		patchOps.AppendAdd("/delivered_at", *patch.DeliveredAt)
	}

	response, err := s.commands.PatchItem(ctx, pk, command.ID, patchOps, &azcosmos.ItemOptions{
		EnableContentResponseOnWrite: true,
		IfMatchEtag:                  command.ETag,
	})
	if err != nil {
		var responseErr *azcore.ResponseError
		if errors.As(err, &responseErr) && responseErr.StatusCode == http.StatusPreconditionFailed {
			return store.NewErrPreconditionFailedOnUpdate()
		}
		return err
	}

	err = json.Unmarshal(response.Value, &command)
	if err != nil {
		return err
	}

	return nil
}

// BatchPatchCommands applies a partial update to multiple commands in a single
// transactional batch operation. All commands must belong to the same assignment
// and job. If any command fails to update, none will be updated.
func (s *CosmosJobsStore) BatchPatchCommands(ctx context.Context, commands []*command.Command, patch store.CommandPatch) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.BatchPatchCommands")
	defer span.End()

	if len(commands) == 0 {
		return nil
	}

	// confirm all commands belong to the same assignment and job
	assignmentID := commands[0].AssignmentID
	jobID := commands[0].JobID
	for _, cmd := range commands {
		if cmd.AssignmentID != assignmentID || cmd.JobID != jobID {
			return store.NewErrBatchPartitionKeysMismatch()
		}
	}

	pk := jobPK(assignmentID, jobID)
	batch := s.commands.NewTransactionalBatch(pk)

	for _, cmd := range commands {
		patchOps := azcosmos.PatchOperations{}

		if patch.Status != nil {
			patchOps.AppendAdd("/status", *patch.Status)
		}
		if patch.DeliveredAt != nil {
			patchOps.AppendAdd("/delivered_at", *patch.DeliveredAt)
		}

		batchItemOpts := &azcosmos.TransactionalBatchItemOptions{}
		if cmd.ETag != nil {
			batchItemOpts.IfMatchETag = cmd.ETag
		}

		batch.PatchItem(cmd.ID, patchOps, batchItemOpts)
	}

	response, err := s.commands.ExecuteTransactionalBatch(ctx, batch, &azcosmos.TransactionalBatchOptions{
		EnableContentResponseOnWrite: true,
	})
	if err != nil {
		return err
	}

	if response.Success {
		// update the commands with the new ETags
		for i, opp := range response.OperationResults {
			err = json.Unmarshal(opp.ResourceBody, &commands[i])
			if err != nil {
				return err
			}
		}
		return nil
	}

	var errs []error

	// Batching follows an all-or-nothing approach. If any operation fails,
	// the entire batch is considered failed.
	// If an operation does fail, that operation will have the "real" status
	// code corresponding to the error. All the other operations will have a
	// 424 status code (failed dependency) to indicate they were not executed
	// because of the failure of another operation.
	for _, opp := range response.OperationResults {
		if opp.StatusCode == http.StatusFailedDependency {
			continue // skip failed dependency errors (see comment above)
		}
		errs = append(errs, goerrors.Errorf("failed to patch command with status: %d", opp.StatusCode))
	}

	if len(errs) == 0 {
		return errors.Join(store.NewErrBatchOperationFailed(), goerrors.New("failed to batch patch commands: unknown error"))
	}

	return errors.Join(store.NewErrBatchOperationFailed(), errors.Join(errs...))
}

// getAllItemsFromPager retrieves all items from the pager and unmarshals them into a slice of type T.
func getAllItemsFromPager[T any](ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse]) ([]*T, error) {
	var items []*T

	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}

		for _, item := range response.Items {
			var i *T
			err = json.Unmarshal(item, &i)
			if err != nil {
				return nil, err
			}
			items = append(items, i)
		}
	}

	return items, nil
}

// getSingleItemFromPager retrieves a single item from the pager and returns it as type T.
// If multiple items are found, it returns [errMultipleItemsFoundForQuery] error.
// If no items are found, it returns nil.
func getSingleItemFromPager[T any](ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse]) (*T, error) {
	items, err := getAllItemsFromPager[T](ctx, pager)
	if err != nil {
		return nil, err
	}

	switch len(items) {
	case 0:
		return nil, nil // no item found
	case 1:
		return items[0], nil // single item found
	default:
		return nil, errMultipleItemsFoundForQuery // multiple items found
	}
}

// countAllItemsFromPager counts all items from the pager and returns the total count.
func countAllItemsFromPager(ctx context.Context, pager *runtime.Pager[azcosmos.QueryItemsResponse]) (int, error) {
	count := 0

	for pager.More() {
		response, err := pager.NextPage(ctx)
		if err != nil {
			return 0, err
		}

		count += len(response.Items)
	}

	return count, nil
}

// selectFields constructs a comma-separated string of fields with the given alias.
// example: selectFields([]string{"id", "status"}, "c") returns "c.id, c.status"
func selectFields(fields []string, alias string) string {
	seq := func(yield func(string) bool) {
		for field := range slices.Values(fields) {
			if !yield(alias + "." + field) {
				return
			}
		}
	}
	return strings.Join(slices.Collect(seq), ", ")
}

// HealthCheck verifies connectivity to Cosmos DB by performing a lightweight read operation.
// It returns nil if the connection is healthy, or an error if the connection fails.
func (s *CosmosJobsStore) HealthCheck(ctx context.Context) error {
	ctx, span := s.obsv.Tracer.Start(ctx, "cosmosdb.CosmosJobsStore.HealthCheck")
	defer span.End()

	// Read the container properties to verify connectivity.
	// This is a lightweight operation that doesn't require reading any documents.
	_, err := s.jobs.Read(ctx, nil)
	if err != nil {
		return goerrors.Errorf("failed to connect to Cosmos DB: %w", err)
	}

	return nil
}
