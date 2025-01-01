package runservice

import (
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/workflowbuild/build"

	proto "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
)

func buildGitHubEventInfo(in *build.WorkflowBuild) *proto.GitHubEventInfo {
	out := &proto.GitHubEventInfo{
		CustomerLabel:     in.CustomerLabel,
		InvokingEventType: in.Event,
		InvokingEventTime: timestamppb.New(in.OriginTime),
	}

	abuC := in.AbuseContext
	if abuC == nil {
		return out
	}

	out.AbuseInfo = &proto.AbuseInfo{
		WorkflowExecutionId:  abuC.WorkflowExecutionID,
		WorkflowFilePath:     abuC.WorkflowFilePath,
		WorkflowRunId:        abuC.WorkflowRunID,
		TargetRepositoryTier: uint32(abuC.TargetRepositoryTier),
		TriggerEvent:         abuC.TriggerEvent,
		TriggerEventAction:   abuC.TriggerEventAction,
	}

	if abuC.Actor != nil {
		out.AbuseInfo.Actor = &proto.AbuseInfoIdentity{
			Id:        abuC.Actor.ID,
			Name:      abuC.Actor.Name,
			Type:      abuC.Actor.Type,
			Plan:      abuC.Actor.Plan,
			CreatedAt: abuC.Actor.CreatedAt.Format(time.RFC3339),
			IsHammy:   abuC.Actor.IsHammy,
		}
	}

	if abuC.TargetRepoOwner != nil {
		out.AbuseInfo.TargetRepoOwner = &proto.AbuseInfoIdentity{
			Id:        abuC.TargetRepoOwner.ID,
			Name:      abuC.TargetRepoOwner.Name,
			Type:      abuC.TargetRepoOwner.Type,
			Plan:      abuC.TargetRepoOwner.Plan,
			CreatedAt: abuC.TargetRepoOwner.CreatedAt.Format(time.RFC3339),
			IsHammy:   abuC.TargetRepoOwner.IsHammy,
		}
	}

	if abuC.BillingPlanOwner != nil {
		out.AbuseInfo.BillingPlanOwner = &proto.AbuseInfoIdentity{
			Id:        abuC.BillingPlanOwner.ID,
			Name:      abuC.BillingPlanOwner.Name,
			Type:      abuC.BillingPlanOwner.Type,
			Plan:      abuC.BillingPlanOwner.Plan,
			CreatedAt: abuC.BillingPlanOwner.CreatedAt.Format(time.RFC3339),
			IsHammy:   abuC.BillingPlanOwner.IsHammy,
		}
	}

	if abuC.TargetRepository != nil {
		out.AbuseInfo.TargetRepository = &proto.TargetRepository{
			Id:         abuC.TargetRepository.ID,
			DatabaseId: abuC.TargetRepository.DatabaseID,
			Private:    abuC.TargetRepository.Private,
			Nwo:        abuC.TargetRepository.NWO,
			CreatedAt:  abuC.TargetRepository.CreatedAt.Format(time.RFC3339),
		}
	}

	return out
}
