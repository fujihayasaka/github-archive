package policy

import (
	"context"
	"errors"
	"fmt"
	"slices"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/eventpublisher"
	proto "github.com/github/osslicensecompliance/pkg/proto/v0"
)

// updateResult holds the outcome of a policy update operation
type updateResult struct {
	WasCreated bool
	Actions    []dependencygraphv1.LicensePolicyChanged_PolicyAction
}

// MultipleUpdates provides the input for a policy update that can
// add/delete licenses and packages in a single operation.
type MultipleUpdates struct {
	AddSpdxIDs          []string
	DeleteSpdxIDs       []string
	AddPackages         []*proto.PackagePolicy
	DeletePackages      []*proto.PackagePolicy
	DistributionContext string // Only required for organization and enterprise policies, ignored for repository policies
}

// policyUpdater defines an interface for making changes to a policy for a
// particular level (repository, organization, enterprise)
type policyUpdater interface {
	AddLicenses(licenses []string, distributionContexts []string)
	AddPackage(packagePolicy *proto.PackagePolicy, distributionContexts []string)
	RemoveLicenses(spdxIDs []string, distributionContext string)
	RemovePackages(packages []*proto.PackagePolicy, distributionContext string)
}

// policyUpserter knows how to perform an upsert operation for a specific
// policy level (repository, organization, enterprise).
type policyUpserter func(ctx context.Context, performUpdate func(policyUpdater) updateResult) (updateResult, error)

// Writer provides methods to modify license policies and store the result
type Writer struct {
	app       *application.Application
	publisher *eventpublisher.Publisher
	upserter  policyUpserter
	level     dependencygraphv1.LicensePolicyChanged_PolicyLevel
	entityID  uint64
}

// NewWriter creates a Writer for the specified policy level and entity.
func NewWriter(app *application.Application, level proto.PolicyLevel, entityID uint64) (*Writer, error) {
	switch level {
	case proto.PolicyLevel_POLICY_LEVEL_REPOSITORY:
		upserter := &repositoryUpserter{
			storage:      app.Subsystems.Storage,
			repositoryID: entityID,
		}
		return &Writer{
			app:       app,
			publisher: app.Subsystems.EventPublisher,
			upserter:  upserter.Upsert,
			level:     dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY,
			entityID:  entityID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ORGANIZATION:
		upserter := &organizationUpserter{
			storage:        app.Subsystems.Storage,
			organizationID: entityID,
		}
		return &Writer{
			app:       app,
			publisher: app.Subsystems.EventPublisher,
			upserter:  upserter.Upsert,
			level:     dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_ORGANIZATION,
			entityID:  entityID,
		}, nil
	case proto.PolicyLevel_POLICY_LEVEL_ENTERPRISE:
		upserter := &enterpriseUpserter{
			storage:      app.Subsystems.Storage,
			enterpriseID: entityID,
		}
		return &Writer{
			app:       app,
			publisher: app.Subsystems.EventPublisher,
			upserter:  upserter.Upsert,
			level:     dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_ENTERPRISE,
			entityID:  entityID,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported policy level: %v", level)
	}
}

// AddLicenses adds licenses to the policy for the specified distribution contexts.
func (w *Writer) AddLicenses(ctx context.Context, licenses, distributionContexts []string) error {
	return w.doUpdate(ctx, distributionContexts, func(u policyUpdater) updateResult {
		u.AddLicenses(licenses, distributionContexts)
		return updateResult{Actions: []dependencygraphv1.LicensePolicyChanged_PolicyAction{dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_ADDED}}
	})
}

// AddPackage adds a package exemption to the policy for the specified distribution contexts.
func (w *Writer) AddPackage(ctx context.Context, packagePolicy *proto.PackagePolicy, distributionContexts []string) error {
	return w.doUpdate(ctx, distributionContexts, func(u policyUpdater) updateResult {
		u.AddPackage(packagePolicy, distributionContexts)
		return updateResult{Actions: []dependencygraphv1.LicensePolicyChanged_PolicyAction{dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_ADDED}}
	})
}

// RemoveLicenses removes licenses from the policy for the specified distribution context.
func (w *Writer) RemoveLicenses(ctx context.Context, spdxIDs []string, distributionContext string) error {
	if distributionContext == "" && w.level != dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY {
		return ErrDistributionContextRequired
	}
	return w.doUpdate(ctx, []string{distributionContext}, func(u policyUpdater) updateResult {
		u.RemoveLicenses(spdxIDs, distributionContext)
		return updateResult{Actions: []dependencygraphv1.LicensePolicyChanged_PolicyAction{dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_REMOVED}}
	})
}

// RemovePackages removes package exemptions from the policy for the specified distribution context.
func (w *Writer) RemovePackages(ctx context.Context, packages []*proto.PackagePolicy, distributionContext string) error {
	if distributionContext == "" && w.level != dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY {
		return ErrDistributionContextRequired
	}
	return w.doUpdate(ctx, []string{distributionContext}, func(u policyUpdater) updateResult {
		u.RemovePackages(packages, distributionContext)
		return updateResult{Actions: []dependencygraphv1.LicensePolicyChanged_PolicyAction{dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_REMOVED}}
	})
}

// UpdateMultiple performs multiple updates (add/remove licenses and packages) in a single operation.
func (w *Writer) UpdateMultiple(ctx context.Context, updates *MultipleUpdates) error {
	if updates == nil {
		return errors.New("updates cannot be nil")
	}
	if updates.DistributionContext == "" && w.level != dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY {
		return ErrDistributionContextRequired
	}
	return w.doUpdate(ctx, []string{updates.DistributionContext}, func(u policyUpdater) updateResult {
		var actions []dependencygraphv1.LicensePolicyChanged_PolicyAction
		// Do adds before deletes in case the policy doesn't exist yet
		if len(updates.AddSpdxIDs) > 0 {
			u.AddLicenses(updates.AddSpdxIDs, []string{updates.DistributionContext})
			actions = append(actions, dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_ADDED)
		}
		if len(updates.AddPackages) > 0 {
			for _, pkg := range updates.AddPackages {
				u.AddPackage(pkg, []string{updates.DistributionContext})
				actions = append(actions, dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_ADDED)
			}
		}
		if len(updates.DeleteSpdxIDs) > 0 {
			u.RemoveLicenses(updates.DeleteSpdxIDs, updates.DistributionContext)
			actions = append(actions, dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_LICENSE_REMOVED)
		}
		if len(updates.DeletePackages) > 0 {
			u.RemovePackages(updates.DeletePackages, updates.DistributionContext)
			actions = append(actions, dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_PACKAGE_EXEMPTION_REMOVED)
		}
		return updateResult{Actions: actions}
	})
}

// doUpdate has the common logic for running an update and publishing the resulting events.
func (w *Writer) doUpdate(ctx context.Context, distributionContexts []string, updateFunc func(u policyUpdater) updateResult) error {
	result, err := w.upserter(ctx, updateFunc)
	if err != nil {
		return fmt.Errorf("failed to run update on %s policy: %w", w.level.String(), err)
	}
	actions := result.Actions
	if result.WasCreated {
		actions = slices.Insert(actions, 0, dependencygraphv1.LicensePolicyChanged_POLICY_ACTION_POLICY_CREATED)
	}
	if w.level == dependencygraphv1.LicensePolicyChanged_POLICY_LEVEL_REPOSITORY {
		distributionContexts = nil // Distribution contexts are not relevant for repository-level policies in the event payload, as they are always applied at the repository level. Setting to nil to avoid confusion.
	}
	for _, action := range actions {
		publishPolicyChangedAsync(ctx, w.app, w.publisher, eventpublisher.PolicyChangedEvent{
			Action:               action,
			Level:                w.level,
			EntityID:             w.entityID,
			DistributionContexts: distributionContexts,
		})
	}
	return nil
}
