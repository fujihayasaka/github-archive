// Package resource contains the domain logic for parsing and loading resource payloads
package resource

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/assets"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/migrationctx"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	// Loader is an interface that defines the methods exposed by this package
	// to load resources
	Loader interface {
		LoadResource(ctx context.Context, resource *v1.Resource) error
	}

	// LoaderImpl is a struct that can be used to load resources
	LoaderImpl struct {
		importClient      client.Importer
		kvResolver        KVResolver
		dag               dag.DAG
		enterpriseID      int64
		logger            log.Logger
		statter           stats.Client
		intermediateStore *blobstore.Store
		uploader          assets.Uploader
	}

	// KVResolver is an interface that defines the methods that are required to keep track
	// of the resource IDs translations
	KVResolver interface {
		AddInt64Resource(ctx context.Context, namespace, key string, value int64) error
		ResolveInt64Resource(ctx context.Context, namespace, key string) (int64, error)
		AddStringResource(ctx context.Context, namespace, key string, value string) error
		ResolveStringResource(ctx context.Context, namespace, key string) (string, error)
		ResourceExists(ctx context.Context, namespace, key string) (bool, error)
	}
)

// NewLoaderImpl returns a new LoaderImpl that can be used to load
// resources.
func NewLoaderImpl(opts ...Option) *LoaderImpl {
	r := &LoaderImpl{
		logger:  log.NewNullLogger(),
		statter: stats.NullStatter,
	}

	for _, opt := range opts {
		opt(r)
	}
	r.logger = r.logger.WithFields(kvp.String("component", "resource-loader"))

	if r.importClient == nil {
		r.importClient = &client.DummyImporter{Logger: r.logger}
	}

	return r
}

// LoadResource loads a resource from the given v1.Resource payload by
// inspecting the type of the resource and calling the appropriate method.
//
//nolint:maintidx // this handles multiple resource types and their dependencies, making it inherently complex until refactored
func (l *LoaderImpl) LoadResource(ctx context.Context, resource *v1.Resource) error {
	ns, err := migrationctx.Namespace(resource)
	if err != nil {
		l.logger.WithError(err).Error("error getting namespace")
		return fmt.Errorf("error getting namespace: %w", err)
	}
	adminUserID, err := migrationctx.AdminUserID(resource)
	if err != nil {
		l.logger.WithError(err).Error("error getting admin user ID")
		return fmt.Errorf("error getting admin user ID: %w", err)
	}

	logger := l.logger.WithFields(kvp.String("namespace", ns))
	switch r := resource.Resource.(type) {
	case *v1.Resource_Organization:
		logger = l.logger.WithFields(kvp.String("type", "organization"),
			kvp.String("resource_id", r.Organization.ResourceId))
		if err = l.handle(ctx, ns, newOrganization(r.Organization, adminUserID, l.enterpriseID, logger)); err != nil {
			err = fmt.Errorf("failed to load organization: %w", err)
		}
	case *v1.Resource_InitialOrganizationSettings:
		logger = l.logger.WithFields(kvp.String("type", "organizationsettings"),
			kvp.String("resource_id", r.InitialOrganizationSettings.ResourceId))
		if err = l.handle(ctx, ns, newInitialOrganizationSettings(r.InitialOrganizationSettings, logger)); err != nil {
			err = fmt.Errorf("failed to load organization settings: %w", err)
		}
	case *v1.Resource_Repository:
		logger = l.logger.WithFields(kvp.String("type", "repository"),
			kvp.String("resource_id", r.Repository.ResourceId))
		if err = l.handle(ctx, ns, newRepository(r.Repository, adminUserID, logger)); err != nil {
			err = fmt.Errorf("failed to load repository: %w", err)
		}
	case *v1.Resource_ProtectedBranch:
		logger = l.logger.WithFields(kvp.String("type", "protected_branch"),
			kvp.String("resource_id", r.ProtectedBranch.ResourceId))
		if err = l.handle(ctx, ns, newProtectedBranch(r.ProtectedBranch, logger)); err != nil {
			err = fmt.Errorf("failed to load protected branch: %w", err)
		}
	case *v1.Resource_InitialRepositorySettings:
		logger = l.logger.WithFields(kvp.String("type", "repositorysettings"),
			kvp.String("resource_id", r.InitialRepositorySettings.ResourceId))
		if err = l.handle(ctx, ns, newInitialRepositorySettings(r.InitialRepositorySettings, logger)); err != nil {
			err = fmt.Errorf("failed to load repository settings: %w", err)
		}
	case *v1.Resource_InitialActionsSettings:
		logger = l.logger.WithFields(kvp.String("type", "actionssettings"),
			kvp.String("resource_id", r.InitialActionsSettings.ResourceId))
		if err = l.handle(ctx, ns, newInitialActionsSettings(r.InitialActionsSettings, logger)); err != nil {
			err = fmt.Errorf("failed to load actions settings: %w", err)
		}
	case *v1.Resource_Mannequin:
		logger = l.logger.WithFields(kvp.String("type", "mannequin"),
			kvp.String("resource_id", r.Mannequin.ResourceId))
		if err = l.handle(ctx, ns, newMannequin(r.Mannequin, logger)); err != nil {
			err = fmt.Errorf("failed to load mannequin: %w", err)
		}
	case *v1.Resource_Team:
		logger = l.logger.WithFields(kvp.String("type", "team"),
			kvp.String("resource_id", r.Team.ResourceId))
		if err = l.handle(ctx, ns, newTeam(r.Team, logger)); err != nil {
			err = fmt.Errorf("failed to load team: %w", err)
		}
	case *v1.Resource_Issue:
		logger = l.logger.WithFields(kvp.String("type", "issue"),
			kvp.String("resource_id", r.Issue.ResourceId))
		if err = l.handle(ctx, ns, newIssue(r.Issue, logger)); err != nil {
			err = fmt.Errorf("failed to load issue: %w", err)
		}
	case *v1.Resource_PullRequest:
		logger = l.logger.WithFields(kvp.String("type", "pull_request"),
			kvp.String("resource_id", r.PullRequest.ResourceId))
		if err = l.handle(ctx, ns, newPullRequest(r.PullRequest, logger)); err != nil {
			err = fmt.Errorf("failed to load pr: %w", err)
		}
	case *v1.Resource_PullRequestReview:
		logger = l.logger.WithFields(kvp.String("type", "pull_request_review"),
			kvp.String("resource_id", r.PullRequestReview.ResourceId))
		if err = l.handleBatch(ctx, ns, newPullRequestReview(r.PullRequestReview, logger)); err != nil {
			err = fmt.Errorf("failed to load pr review: %w", err)
		}
	case *v1.Resource_IssueComment:
		logger = l.logger.WithFields(kvp.String("type", "issue_comment"),
			kvp.String("resource_id", r.IssueComment.ResourceId))
		if err = l.handle(ctx, ns, newIssueComment(r.IssueComment, logger)); err != nil {
			err = fmt.Errorf("failed to load issue comment: %w", err)
		}
	case *v1.Resource_IssueEventBatch:
		logger = l.logger.WithFields(kvp.String("type", "issue_event_batch"),
			kvp.String("resource_id", r.IssueEventBatch.ResourceId))
		if err = l.handleBatch(ctx, ns, newIssueEventBatch(r.IssueEventBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load issue event batch: %w", err)
		}
	case *v1.Resource_MilestoneBatch:
		logger = l.logger.WithFields(kvp.String("type", "milestone_batch"),
			kvp.String("resource_id", r.MilestoneBatch.ResourceId))
		if err = l.handleBatch(ctx, ns, newMilestoneBatch(r.MilestoneBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load milestone batch: %w", err)
		}
	case *v1.Resource_Attachment:
		logger = l.logger.WithFields(kvp.String("type", "attachment"),
			kvp.String("resource_id", r.Attachment.ResourceId))
		if err = l.handle(ctx, ns, newAttachment(r.Attachment, logger)); err != nil {
			err = fmt.Errorf("failed to load attachment: %w", err)
		}
	case *v1.Resource_RepositoryLabelsBatch:
		logger = l.logger.WithFields(kvp.String("type", "repository_labels_batch"),
			kvp.String("resource_id", r.RepositoryLabelsBatch.ResourceId))
		if err = l.handleBatch(ctx, ns, newRepositoryLabelsBatch(r.RepositoryLabelsBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load repos labels: %w", err)
		}
	case *v1.Resource_Project:
		logger = l.logger.WithFields(kvp.String("type", "project"),
			kvp.String("resource_id", r.Project.ResourceId))
		if err = l.handle(ctx, ns, newProject(r.Project, logger)); err != nil {
			err = fmt.Errorf("failed to load project: %w", err)
		}
	case *v1.Resource_ProjectColumn:
		logger = l.logger.WithFields(kvp.String("type", "project_column"),
			kvp.String("resource_id", r.ProjectColumn.ResourceId))
		if err = l.handle(ctx, ns, newProjectColumn(r.ProjectColumn, logger)); err != nil {
			err = fmt.Errorf("failed to load project column: %w", err)
		}
	case *v1.Resource_ProjectCardsBatch:
		logger = l.logger.WithFields(kvp.String("type", "project_cards_batch"),
			kvp.String("resource_id", r.ProjectCardsBatch.ResourceId))
		if err = l.handle(ctx, ns, newProjectCardsBatch(r.ProjectCardsBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load project cards batch: %w", err)
		}
	case *v1.Resource_IssueLabelsBatch:
		logger = l.logger.WithFields(kvp.String("type", "issue_labels_batch"),
			kvp.String("resource_id", r.IssueLabelsBatch.ResourceId))
		if err = l.handle(ctx, ns, newIssueLabelsBatch(r.IssueLabelsBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load issue labels: %w", err)
		}
	case *v1.Resource_CommitComment:
		logger = l.logger.WithFields(kvp.String("type", "commit_comment"),
			kvp.String("resource_id", r.CommitComment.ResourceId))
		if err = l.handle(ctx, ns, newCommitComment(r.CommitComment, logger)); err != nil {
			err = fmt.Errorf("failed to load commit comment: %w", err)
		}
	case *v1.Resource_ReactionsBatch:
		logger = l.logger.WithFields(kvp.String("type", "reactions_batch"),
			kvp.String("resource_id", r.ReactionsBatch.ResourceId))
		if err = l.handle(ctx, ns, newReactionsBatch(r.ReactionsBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load reactions batch: %w", err)
		}
	case *v1.Resource_CloseIssueReferenceBatch:
		logger = l.logger.WithFields(kvp.String("type", "close_issue_reference_batch"),
			kvp.String("resource_id", r.CloseIssueReferenceBatch.ResourceId))
		if err = l.handleBatch(ctx, ns, newCloseIssueReferenceBatch(r.CloseIssueReferenceBatch, logger)); err != nil {
			err = fmt.Errorf("failed to load close issue references :%w", err)
		}
	case *v1.Resource_Release:
		logger = l.logger.WithFields(kvp.String("type", "release"),
			kvp.String("resource_id", r.Release.ResourceId))
		if err = l.handle(ctx, ns, newRelease(r.Release, logger)); err != nil {
			err = fmt.Errorf("failed to load release: %w", err)
		}
	case *v1.Resource_ReleaseAsset:
		logger = l.logger.WithFields(kvp.String("type", "release_asset"),
			kvp.String("resource_id", r.ReleaseAsset.ResourceId))
		if err = l.handle(ctx, ns, newReleaseAsset(r.ReleaseAsset, logger, l.intermediateStore, l.uploader)); err != nil {
			err = fmt.Errorf("failed to load release asset: %w", err)
		}
	case *v1.Resource_Noop:
		logger = l.logger.WithFields(kvp.String("type", "noop"),
			kvp.String("resource_id", r.Noop.ResourceId))
		if err = l.markAsProcessed(ctx, ns, idsToResourceNodes(r.Noop.ResourceId)); err != nil {
			err = fmt.Errorf("failed to mark as processed: %w", err)
		}
	default:
		err = fmt.Errorf("unknown resource type: %T", r)
	}
	if err != nil {
		logger.WithError(err).Error("failed to load resource")
	}
	return err
}

// markAsProcessed marks the given resource IDs as processed if a DAG is configured.
func (l *LoaderImpl) markAsProcessed(ctx context.Context, namespace string, nodes []dag.Node) error {
	if l.dag == nil {
		return nil
	}
	return l.dag.MarkAsProcessed(ctx, namespace, nodes)
}

// preCheck checks if the resource is already loaded and marks the node as processed if it is.
// this helps us to make the process a bit more–but not completely–idempotent.
func (l *LoaderImpl) preCheck(ctx context.Context, namespace, id string) (bool, error) {
	// check if the resource is already loaded
	ok, err := l.kvResolver.ResourceExists(ctx, namespace, id)
	if err != nil {
		return false, fmt.Errorf("failed to check if resource is loaded: %w", err)
	}
	if !ok {
		return false, nil
	}
	// if it's already loaded, make sure we mark the node as processed
	if err = l.markAsProcessed(ctx, namespace, idsToResourceNodes(id)); err != nil {
		return false, fmt.Errorf("failed to mark as processed: %w", err)
	}
	return true, nil
}

// updateDependencies updates the resolver with the new transformed values
func (l *LoaderImpl) updateDependencies(ctx context.Context, namespace string, transformed resolvedIDsByResource) error {
	for k, v := range transformed {
		if v.strVal != "" {
			if err := l.kvResolver.AddStringResource(ctx, namespace, k, v.strVal); err != nil {
				return fmt.Errorf("failed to add string resource: %w", err)
			}
		}
		if v.int64Val != 0 {
			if err := l.kvResolver.AddInt64Resource(ctx, namespace, k, v.int64Val); err != nil {
				return fmt.Errorf("failed to add int64 resource: %w", err)
			}
		}
	}
	return nil
}

// handle loads a single resource using the given handler.
//
// This function takes following steps:
//
//  1. Check if the resource is already loaded using preCheck, if it is, it skips any further processing.
//
//  2. Fetch the dependencies of the resource using the handler's dependencies method. These dependencies
//     indicate the transformed values that are required to load the resource. E.g: the target IDs that are needed.
//
//  3. Resolve the dependencies using the KVResolver "atomically" to get the transformed values. If any of the
//     dependencies are not resolved, it will return an error.
//
//  4. Transform the resource using the handler's transform method.
//
//  5. Load the resource using the handler's load method.
//
//  6. Update the resolver with the new transformed values using the handler's newResolvedIDs method. These values
//     will be used by the dependants to load their resources.
//
//  7. Mark the resource as processed using the DAG if it's configured.
func (l *LoaderImpl) handle(ctx context.Context, namespace string, h handler) error {
	logger := l.logger.WithFields(kvp.String("resource_id", h.resourceID()))
	logger.Info("handling resource")

	// Check if the resource is already loaded
	ok, err := l.preCheck(ctx, namespace, h.resourceID())
	if err != nil {
		return fmt.Errorf("failed to check if resource is already loaded: %w", err)
	}
	if ok {
		logger.Info("resource already loaded, skipping")
		return nil
	}

	// Resolve dependencies
	dependencies, err := h.dependencies()
	if err != nil {
		return fmt.Errorf("failed to get dependencies: %w", err)
	}
	resolved, err := l.resolveDependencies(ctx, namespace, dependencies)
	if err != nil {
		return fmt.Errorf("failed to resolve dependencies: %w", err)
	}
	logger.Info("dependencies resolved", kvp.Any("dependencies", resolved))

	// Transform
	if err := h.transform(resolved); err != nil {
		return fmt.Errorf("failed to transform resource: %w", err)
	}

	// Load resource using import API
	if err := h.load(ctx, l.importClient, resolved); err != nil {
		return fmt.Errorf("failed to load resource: %w", err)
	}

	// Update resolver with the new imported values
	dependenciesToUpdate := h.newResolvedIDs()
	if err := l.updateDependencies(ctx, namespace, dependenciesToUpdate); err != nil {
		return fmt.Errorf("failed to update resolver with new dependencies: %w", err)
	}

	// Mark resource as processed
	if err := l.markAsProcessed(ctx, namespace, idsToResourceNodes(h.resourceID())); err != nil {
		return fmt.Errorf("failed to mark resource as processed: %w", err)
	}
	logger.Info("resource marked as processed", kvp.Any("new_resolved_ids", dependenciesToUpdate))

	return nil
}

// handleBatch loads a  batched resource using the given batchHandler.
//
// This function takes following steps:
//
//  1. Check if the resource is already loaded using its batchID and preCheck, if it is, it skips any further processing.
//
//  2. Check if any of the items in the batch are already loaded using its itemIDs and preCheck, if they are,
//    they are added to the alreadyLoadedItems set that is passed to the dependencies and transform methods.

//  3. Fetch the dependencies of the resource using the handler's dependencies method. These dependencies
//     indicate the transformed values that are required to load the resource. E.g: the target IDs that are needed.
//
//  4. Resolve the dependencies using the KVResolver "atomically" to get the transformed values. If any of the
//     dependencies are not resolved, it will return an error.
//
// 5. Transform the resource using the handler's transform method.
//
//  6. Load the resource using the handler's load method. If the load fails with a partial error, it will return
//     a PartialBatchError that contains the failed item IDs.
//
//  8. Update the resolver with the new transformed values using the handler's newResolvedIDs method. These values
//     will be used by the dependants to load their resources.
//
//  9. Mark the successful items as processed using the DAG if it's configured. If the load failed with a partial error,
//     it will skip the failed items.
//
// 10. If all items have been successfully loaded, mark the resource as processed using the DAG if it's configured.
func (l *LoaderImpl) handleBatch(ctx context.Context, namespace string, h batchHandler) error {
	logger := l.logger.WithFields(kvp.String("resource_id", h.batchID()), kvp.Bool("is_batch", true))
	logger.Info("handling batch resource")

	// check if the resource is already loaded
	ok, err := l.preCheck(ctx, namespace, h.batchID())
	if err != nil {
		return fmt.Errorf("failed to check if resource is already loaded: %w", err)
	}
	if ok {
		logger.Info("resource already loaded, skipping")
		return nil
	}

	// check if any of the items in the batch are already loaded
	alreadyLoadedItems := make(idSet)
	var notLoadedItems []string
	for _, id := range h.itemIDs() {
		ok, err := l.preCheck(ctx, namespace, id)
		if err != nil {
			return fmt.Errorf("failed to check if item is already loaded: %w", err)
		}
		if ok {
			alreadyLoadedItems[id] = struct{}{}
			continue
		}
		notLoadedItems = append(notLoadedItems, id)
	}
	logger.Info("batch items", kvp.Any("loaded", alreadyLoadedItems), kvp.Any("not_loaded", notLoadedItems))

	// Resolve dependencies
	dependencies, err := h.dependencies(alreadyLoadedItems)
	if err != nil {
		return fmt.Errorf("failed to get dependencies: %w", err)
	}
	resolved, err := l.resolveDependencies(ctx, namespace, dependencies)
	if err != nil {
		return fmt.Errorf("failed to resolve dependencies: %w", err)
	}
	logger.Info("dependencies resolved", kvp.Any("dependencies", resolved))

	// Transform
	if err := h.transform(alreadyLoadedItems, resolved); err != nil {
		return fmt.Errorf("failed to transform resource: %w", err)
	}

	// Load resource using import API
	var partialErr *PartialBatchError
	if err = h.load(ctx, l.importClient, alreadyLoadedItems, resolved); err != nil {
		// if the error is not a partial batch error, just return
		if !errors.As(err, &partialErr) {
			return fmt.Errorf("failed to load resource: %w", err)
		}
		// if the error is a partial batch error, log the failed items
		logger.WithError(partialErr).Error("partial batch error", kvp.Any("failed_items", partialErr.failedItems))
	}

	// Update resolver with the new imported values
	dependenciesToUpdate := h.newResolvedIDs()
	if err := l.updateDependencies(ctx, namespace, dependenciesToUpdate); err != nil {
		return fmt.Errorf("failed to update resolver with new dependencies: %w", err)
	}
	logger.Info("resolver updated")

	// Mark successful items as processed
	var successfulItems []string
	for _, id := range h.itemIDs() {
		if _, ok := alreadyLoadedItems[id]; ok {
			continue
		}
		if partialErr != nil {
			if _, ok := partialErr.failedItems[id]; ok {
				continue
			}
		}
		successfulItems = append(successfulItems, id)
	}
	if err := l.markAsProcessed(ctx, namespace, idsToResourceNodes(successfulItems...)); err != nil {
		return fmt.Errorf("failed to mark successful items as processed: %w", err)
	}
	logger.Info("batch items resources marked as processed",
		kvp.Any("items", successfulItems), kvp.Any("new_resolved_ids", dependenciesToUpdate))

	// Mark resource as processed only if all items in the batch were loaded
	if partialErr != nil {
		return fmt.Errorf("failed to load batch resource: %w", partialErr)
	}

	if err := l.markAsProcessed(ctx, namespace, idsToResourceNodes(h.batchID())); err != nil {
		return fmt.Errorf("failed to mark resource as processed: %w", err)
	}
	logger.Info("batch resource marked as processed", kvp.Any("new_resolved_ids", dependenciesToUpdate))

	return nil
}

func (l *LoaderImpl) resolveDependencies(ctx context.Context, namepsace string, deps *transformedDeps) (resolvedIDsByResource, error) {
	resolved := make(resolvedIDsByResource)
	if deps == nil {
		return resolved, nil
	}
	for _, id := range deps.int64Deps.ToSlice() {
		val, err := l.kvResolver.ResolveInt64Resource(ctx, namepsace, id)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve int64 dependency: %w", err)
		}
		if _, ok := resolved[id]; !ok {
			resolved[id] = &transformedValues{}
		}
		resolved[id].int64Val = val
	}
	for _, id := range deps.strDeps.ToSlice() {
		val, err := l.kvResolver.ResolveStringResource(ctx, namepsace, id)
		if err != nil {
			return nil, fmt.Errorf("failed to resolve str dependency: %w", err)
		}
		if _, ok := resolved[id]; !ok {
			resolved[id] = &transformedValues{}
		}
		resolved[id].strVal = val
	}
	return resolved, nil
}

func valueStrSlice(m resolvedIDsByResource, ks []string) []string {
	var r []string
	for _, k := range ks {
		if v, ok := m[k]; ok {
			r = append(r, v.strVal)
		}
	}
	return r
}

// idsToResourceNodes converts a slice of strings to a slice of dag.Nodes
// which represent ResourceNodes. The loader handles a static snapshot
// of resources and will never handle events, so forcing ResourceNode
// is okay.
func idsToResourceNodes(ids ...string) []dag.Node {
	nodes := make([]dag.Node, 0, len(ids))
	for _, id := range ids {
		nodes = append(nodes, dag.Node{ID: dag.ID(id), Kind: dag.ResourceNode})
	}
	return nodes
}
