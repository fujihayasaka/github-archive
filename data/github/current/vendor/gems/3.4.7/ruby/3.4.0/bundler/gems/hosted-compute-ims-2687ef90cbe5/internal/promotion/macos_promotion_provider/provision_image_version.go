package macos_promotion_provider

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/maccloud-go-core/maccloud/generated/mcp"
	mcpModels "github.com/github/maccloud-go-core/maccloud/generated/models"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
)

type ImagePromotionInFlight struct {
	// Fields to be saved to the state details
	OperationId    *string       `json:"operationId"`
	MCPInstanceUrl *string       `json:"mcpInstanceUrl"`
	RetryDuration  time.Duration `json:"retryDuration"`

	// Internal fields
	StartTimeStamp time.Time                  `json:"-"`
	Status         *mcpModels.OperationStatus `json:"-"`
	MCPInstance    *MCPInstance               `json:"-"`
}

// ProvisionImageVersion promotes the image version to all the MCP instances.
// The failure tolerance for mcp ack is 0 and for host promotion the failure tolerance is 90%
func (p *macOSPromotionProvider) ProvisionImageVersion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, resourceId string) *PromotionError {
	err := p.imagesStore.UpdateImageVersion(ctx, imageVersion.Id, &store.ImageVersionUpdatePayload{
		ResourceId: wrapperspb.String(resourceId),
	})
	if err != nil {
		return &PromotionError{
			Err:          fmt.Errorf("failed to set resource id for image version"),
			NonRetryable: true,
		}
	}

	var inFlightPromotionRequests []*ImagePromotionInFlight
	var retryDuration *time.Duration
	if imageVersion.StateDetails == "" {
		// Start the promotion to all the MCP instances.
		inFlightPromotionRequests, retryDuration, err = p.startImagePromotion(ctx, imageDefinition, imageVersion, resourceId)
		if err != nil {
			return &PromotionError{
				Err:          fmt.Errorf("failed to start image promotion: %w", err),
				NonRetryable: true,
			}
		}

	} else {
		// Resume from the state details.
		inFlightPromotionRequests, retryDuration, err = p.resumeFromState(imageVersion.StateDetails)
		if err != nil {
			return &PromotionError{
				Err:          fmt.Errorf("failed to resume from state: %w", err),
				NonRetryable: true,
			}
		}
	}

	for {
		// Check the status of the promotion requests.
		complete, err := p.checkPromotionStatus(ctx, inFlightPromotionRequests)
		if err != nil {
			return &PromotionError{
				Err:          fmt.Errorf("failed to check promotion status: %w", err),
				NonRetryable: true,
			}
		}

		// If promotion is not in progress return success
		if complete {
			logger.Info(ctx, "promotion completed", kvp.Uint64("image_version_id", imageVersion.Id))
			return nil
		}

		// Save the in-flight promotion requests to the image version state details.
		jsonInFlightPromotionRequests, err := json.Marshal(inFlightPromotionRequests)
		if err != nil {
			logger.ErrorWithReport(ctx, "failed to marshal in-flight promotion requests", err)
		}
		err = p.imagesStore.UpdateImageVersionStateDetailsForState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning, string(jsonInFlightPromotionRequests))
		if err != nil {
			// If we fail to save the state details, the error is logged and we continue with the promotion.
			// State is used for resuming the promotion in case of service restart. If the state is not saved, the promotion will start from the beginning.
			logger.ErrorWithReport(ctx, "failed to update image version state details", err)
		}

		// Wait for retryTimeout duration before checking again.
		time.Sleep(*retryDuration)
	}
}

func (p *macOSPromotionProvider) startImagePromotion(ctx context.Context, imageDefinition *models.ImageDefinition, imageVersion *models.ImageVersion, resourceId string) ([]*ImagePromotionInFlight, *time.Duration, error) {
	var inFlightPromotionRequests []*ImagePromotionInFlight
	for _, instance := range p.mcpInstances {
		instanceRes, err := instance.Client.PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: ArchitectureToMCPArchitecture(imageDefinition.Architecture),
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				ResourceId:        resourceId,
			},
		})
		if err != nil {
			return nil, nil, err
		}

		inFlightPromotionRequests = append(inFlightPromotionRequests, &ImagePromotionInFlight{
			StartTimeStamp: time.Now(),
			OperationId:    &instanceRes.Operation.Id,
			Status:         &instanceRes.Operation.Status,
			MCPInstanceUrl: &instance.InstanceURL,
			RetryDuration:  time.Duration(instanceRes.Operation.RetryAfterSeconds) * time.Second,
			MCPInstance:    instance,
		})
	}

	return inFlightPromotionRequests, &inFlightPromotionRequests[0].RetryDuration, nil
}

func (p *macOSPromotionProvider) resumeFromState(stateDetails string) ([]*ImagePromotionInFlight, *time.Duration, error) {
	// Wait for retryTimeout duration before checking again.
	var inFlightPromotionRequests []*ImagePromotionInFlight
	err := json.Unmarshal([]byte(stateDetails), &inFlightPromotionRequests)
	if err != nil {
		return nil, nil, err
	}

	// Check if each instance has operationId set
	for _, request := range inFlightPromotionRequests { // Find Client for the MCP Url
		for _, instance := range p.mcpInstances {
			if instance.InstanceURL == *request.MCPInstanceUrl {
				request.MCPInstance = instance
				break
			}
		}

		if request.MCPInstance == nil {
			return nil, nil, errors.New("failed to find mcp instance client for mcp instance")
		}
	}

	return inFlightPromotionRequests, &inFlightPromotionRequests[0].RetryDuration, nil
}

func (p *macOSPromotionProvider) checkPromotionStatus(ctx context.Context, inFlightPromotionRequests []*ImagePromotionInFlight) (bool, error) {
	// Collect the status of each promotion request.
	for _, request := range inFlightPromotionRequests {
		statusRes, err := request.MCPInstance.Client.GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: *request.OperationId,
		})
		if err != nil {
			// Continue collecting status of other promotion requests.
			logger.ErrorWithReport(ctx, "failed to get operation status", err)
			continue
		}
		if statusRes.Operation.ExpireAfter != nil && statusRes.Operation.ExpireAfter.AsTime().Before(time.Now()) {
			timeout := mcpModels.OperationStatus_TIMEOUT
			request.Status = &timeout
			continue
		}

		request.Status = &statusRes.Operation.Status
	}

	// Consolidate the status of each promotion request and check if all promotions have completed.
	var allResolved bool = true
	var successCount int
	for _, request := range inFlightPromotionRequests {
		switch *request.Status {
		case mcpModels.OperationStatus_SUCCEEDED:
			// Promotion is successful
			logger.Info(ctx, "promotion succeeded", kvp.String("mcp_instance", request.MCPInstance.InstanceURL))
			successCount++
		case mcpModels.OperationStatus_FAILED:
			// Promotion failed, logging the error and continue checking.
			logger.ErrorWithReport(ctx, "promotion failed", fmt.Errorf("failed to promote image version to mcp instance %s", request.MCPInstance.InstanceURL))
		case mcpModels.OperationStatus_TIMEOUT:
			// Promotion timed out, logging the error and continue checking.
			logger.ErrorWithReport(ctx, "promotion timed out", fmt.Errorf("timed out promoting image version to mcp instance %s", request.MCPInstance.InstanceURL))
		case mcpModels.OperationStatus_REQUESTED:
			// Promotion is still in progress, continue checking.
			allResolved = false
		case mcpModels.OperationStatus_IN_PROGRESS:
			// Promotion is still in progress, continue checking.
			allResolved = false
		}
	}

	if allResolved {
		logger.Info(ctx, "all promotions have completed", kvp.Int("success_count", successCount), kvp.Int("total_count", len(inFlightPromotionRequests)))
		// Calculate the percentage of successful promotions
		percentageSuccess := (successCount / len(inFlightPromotionRequests)) * 100
		if percentageSuccess < 90 {
			return allResolved, fmt.Errorf("promotion failed, success percentage: %d", percentageSuccess)
		}
		return allResolved, nil
	}

	return allResolved, nil
}
