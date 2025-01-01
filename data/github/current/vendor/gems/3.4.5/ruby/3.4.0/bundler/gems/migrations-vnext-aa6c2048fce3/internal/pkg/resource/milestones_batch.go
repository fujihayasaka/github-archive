package resource

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type milestoneBatch struct {
	baseBatchHandler
	pb                      *v1.MilestoneBatch
	importedResult          *octov1.ImportMilestonesResponse
	milestoneIDToResourceID map[int64]string
	failedIDs               idSet
}

var _ batchHandler = (*milestoneBatch)(nil)

func newMilestoneBatch(pb *v1.MilestoneBatch, logger log.Logger) *milestoneBatch {
	return &milestoneBatch{
		baseBatchHandler:        baseBatchHandler{logger},
		pb:                      pb,
		milestoneIDToResourceID: make(map[int64]string),
		failedIDs:               make(idSet),
	}
}

func (m *milestoneBatch) batchID() string {
	return m.pb.ResourceId
}

func (m *milestoneBatch) itemIDs() []string {
	var ids []string
	for _, ms := range m.pb.Milestones {
		ids = append(ids, ms.ResourceId)
	}
	return ids
}

func (m *milestoneBatch) dependencies(loaded idSet) (*transformedDeps, error) {
	deps := newTransformedDeps()
	for _, ms := range m.pb.Milestones {
		if _, ok := loaded[ms.ResourceId]; ok {
			continue
		}
		k, err := keys.ToMilestoneKey(ms.ResourceId)
		if err != nil {
			return nil, fmt.Errorf("could not parse issue event key: %w", err)
		}
		deps.int64Deps.Add(k.RepositoryKey.String())
		deps.int64Deps.Add(ms.IssueResourceIds...)
		deps.strDeps.Add(ms.UserResourceId)
	}
	return deps, nil
}

func (m *milestoneBatch) load(ctx context.Context, importer client.Importer, loaded idSet, resolved resolvedIDsByResource) error {
	// Create a mapping of milestone ID to resource ID
	for _, ms := range m.pb.Milestones {
		k, err := keys.ToMilestoneKey(ms.ResourceId)
		if err != nil {
			return fmt.Errorf("failed to parse milestone key: %w", err)
		}
		m.milestoneIDToResourceID[k.MilestoneID] = ms.ResourceId
	}

	// Add the milestones to the batch
	var milestones []*octov1.Milestone
	var repoResourceID string
	for _, ms := range m.pb.Milestones {
		if _, ok := loaded[ms.ResourceId]; ok {
			continue
		}
		k, err := keys.ToMilestoneKey(ms.ResourceId)
		if err != nil {
			return fmt.Errorf("could not parse milestone key: %w", err)
		}

		var issueIDs []int64
		for _, resourceID := range ms.IssueResourceIds {
			issueIDs = append(issueIDs, resolved[resourceID].int64Val)
		}

		milestones = append(milestones, &octov1.Milestone{
			SourceId:           k.MilestoneID,
			Title:              ms.Title,
			CreatedByUserLogin: resolved[ms.UserResourceId].strVal,
			Description:        ms.Description,
			State: func() octov1.MilestoneState {
				switch ms.State {
				case "open":
					return octov1.MilestoneState_MILESTONE_STATE_OPEN
				case "closed":
					return octov1.MilestoneState_MILESTONE_STATE_CLOSED
				default:
					return octov1.MilestoneState_MILESTONE_STATE_INVALID
				}
			}(),
			DueOn:     ms.DueOn,
			CreatedAt: ms.CreatedAt,
			UpdatedAt: ms.UpdatedAt,
			ClosedAt:  ms.ClosedAt,
			IssueIds:  issueIDs,
		})

		repoResourceID = k.RepositoryKey.String()
	}

	// If there are no milestones, return early
	if len(milestones) == 0 {
		return nil
	}

	// Import the batch and save response for later
	req := &octov1.ImportMilestonesRequest{
		RepositoryId: resolved[repoResourceID].int64Val,
		Milestones:   milestones,
	}
	res, err := importer.ImportMilestones(ctx, req)
	if err != nil {
		m.logger.WithError(err).Error("failed to import milestones", kvp.Any("request", req))
		return fmt.Errorf("failed to load milestones batch: %w", err)
	}
	m.importedResult = res

	// If all milestones were imported successfully, we are done
	if len(res.MilestoneErrors) == 0 {
		return nil
	}

	// Some milestones failed to be imported, return a partial batch error containing the validation errors
	// and the IDs of the items that failed
	var failedErrs error
	for _, ms := range res.MilestoneErrors {
		resourceID, ok := m.milestoneIDToResourceID[ms.Milestone.SourceId]
		if !ok {
			return fmt.Errorf("failed to convert milestone source ID to resource ID")
		}
		m.failedIDs[resourceID] = struct{}{}
		for _, id := range ms.ErrorList {
			failedErrs = errors.Join(failedErrs, fmt.Errorf("failed to attribute issue %d to milestone %s ", id, resourceID))
		}
	}
	return &PartialBatchError{
		err:         failedErrs,
		failedItems: m.failedIDs,
	}
}

func (m *milestoneBatch) newResolvedIDs() resolvedIDsByResource {
	depVals := make(resolvedIDsByResource)
	if m.importedResult == nil {
		return depVals
	}
	for _, ms := range m.importedResult.MilestoneMappings {
		resourceID, ok := m.milestoneIDToResourceID[ms.SourceId]
		if !ok {
			continue
		}
		if _, ok := m.failedIDs[resourceID]; ok {
			continue
		}
		depVals[resourceID] = &transformedValues{int64Val: ms.Id}
	}
	return depVals
}
