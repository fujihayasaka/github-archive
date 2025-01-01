package macos_promotion_provider

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/github/maccloud-go-core/maccloud/generated/mcp"
	mcpModels "github.com/github/maccloud-go-core/maccloud/generated/models"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/hosted-compute-ims/internal/models"
)

func TestProvisionImageVersion(t *testing.T) {
	var (
		ctx             = context.Background()
		imageDefinition = &models.ImageDefinition{
			Id:           1,
			OwnerId:      "github",
			ImageType:    models.ImageType_Curated,
			Name:         "test-image",
			Architecture: models.Architecture_X64,
		}
		imageVersion = &models.ImageVersion{
			Id:                1,
			Version:           "1.0.0",
			ImageDefinitionId: 1,
			State:             models.ImageVersionState_Provisioning,
			Enabled:           true,
			ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			StateDetails:      "",
		}
	)

	t.Run("failed to set resource id for image version", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(fmt.Errorf("test"))

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "resource-id")
		assert.ErrorContains(t, err, "failed to set resource id for image version")
	})

	t.Run("success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil).Once()
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_SUCCEEDED,
			},
		}, nil)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Nil(t, err)
	})

	t.Run("failed", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil).Once()
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_FAILED,
			},
		}, nil)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Error(t, err)
		assert.Equal(t, err.NonRetryable, true)
	})

	t.Run("timeout", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil).Once()
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:          operationId,
				Status:      mcpModels.OperationStatus_IN_PROGRESS,
				ExpireAfter: timestamppb.New(time.Now().Add(-1 * time.Minute)),
			},
		}, nil)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Error(t, err)
		assert.Equal(t, err.NonRetryable, true)
	})

	t.Run("returns in progress then success", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil)
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:          operationId,
				Status:      mcpModels.OperationStatus_IN_PROGRESS,
				ExpireAfter: timestamppb.New(time.Now().Add(1 * time.Minute)),
			},
		}, nil).Times(2)
		mockImagesStore.EXPECT().UpdateImageVersionStateDetailsForState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning, gomock.Any()).Return(nil).Times(2)
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:          operationId,
				Status:      mcpModels.OperationStatus_SUCCEEDED,
				ExpireAfter: timestamppb.New(time.Now().Add(1 * time.Minute)),
			},
		}, nil)

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Nil(t, err)
	})

	t.Run("recover from state details", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_IN_PROGRESS,
			},
		}, nil).Once()
		mockImagesStore.EXPECT().UpdateImageVersionStateDetailsForState(ctx, imageVersion.Id, models.ImageVersionState_Provisioning, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_SUCCEEDED,
			},
		}, nil)

		inflightStatus := mcpModels.OperationStatus_IN_PROGRESS
		stateDetails, err := json.Marshal([]ImagePromotionInFlight{
			{
				StartTimeStamp: time.Now(),
				OperationId:    &operationId,
				Status:         &inflightStatus,
				MCPInstanceUrl: &p.mcpInstances[0].InstanceURL,
				RetryDuration:  1 * time.Second,
				MCPInstance:    p.mcpInstances[0],
			},
		})
		assert.Nil(t, err)

		// Dereference the imageVersion to modify for this test
		testImageVersion := *imageVersion
		testImageVersion.StateDetails = string(stateDetails)
		err = p.ProvisionImageVersion(ctx, imageDefinition, &testImageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Nil(t, err)
	})

	t.Run("multiple mcp instances", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		// Add a second mcp instance
		mockSecondMCPClient := mcp.NewMockApi(t)
		p.mcpInstances = append(p.mcpInstances, &MCPInstance{
			InstanceURL: "https://mcp2",
			Client:      mockSecondMCPClient,
		})

		operationId := "operation-id-1"
		operationIdSecond := "operation-id-2"

		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)

		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil).Once()
		mockSecondMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationIdSecond,
			},
		}, nil)

		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_SUCCEEDED,
			},
		}, nil).Once()
		mockSecondMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationIdSecond,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationIdSecond,
				Status: mcpModels.OperationStatus_SUCCEEDED,
			},
		}, nil).Once()

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Nil(t, err)
	})

	t.Run("multiple mcp instances with 50% success rate", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		// Add a second mcp instance
		mockSecondMCPClient := mcp.NewMockApi(t)
		p.mcpInstances = append(p.mcpInstances, &MCPInstance{
			InstanceURL: "https://mcp2",
			Client:      mockSecondMCPClient,
		})

		operationId := uuid.NewString()
		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationId,
			},
		}, nil).Once()
		operationIdSecond := uuid.NewString()
		mockSecondMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(&mcp.PromoteImageVersionResponse{
			Operation: &mcpModels.Operation{
				Id: operationIdSecond,
			},
		}, nil)
		mockMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationId,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationId,
				Status: mcpModels.OperationStatus_SUCCEEDED,
			},
		}, nil).Once()
		mockSecondMCPClient.EXPECT().GetOperation(ctx, &mcp.GetOperationRequest{
			OperationId: operationIdSecond,
		}).Return(&mcp.GetOperationResponse{
			Operation: &mcpModels.Operation{
				Id:     operationIdSecond,
				Status: mcpModels.OperationStatus_FAILED,
			},
		}, nil).Once()

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Error(t, err)
		assert.Equal(t, err.NonRetryable, true)
	})

	t.Run("failed to start promotion", func(t *testing.T) {
		ctrl, p := setup(t)
		defer ctrl.Finish()

		mockImagesStore.EXPECT().UpdateImageVersion(ctx, imageVersion.Id, gomock.Any()).Return(nil)
		mockMCPClient.EXPECT().PromoteImageVersion(ctx, &mcp.PromoteImageVersionRequest{
			ImageDefinition: &mcpModels.ImageDefinition{
				Id:           imageDefinition.Id,
				Name:         imageDefinition.Name,
				CreatedAt:    timestamppb.New(imageDefinition.CreatedAt),
				Architecture: mcpModels.Architecture_X86_64,
			},
			ImageVersion: &mcpModels.ImageVersion{
				Id:                imageVersion.Id,
				Version:           imageVersion.Version,
				ImageDefinitionId: imageVersion.ImageDefinitionId,
				CreatedAt:         timestamppb.New(imageVersion.CreatedAt),
				ResourceId:        "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3",
			},
		}).Return(nil, fmt.Errorf("failed to start promotion")).Once()

		err := p.ProvisionImageVersion(ctx, imageDefinition, imageVersion, "img://65cf40d2-2b21-4e17-bbf9-8902d2b144c3")
		assert.Error(t, err)
	})
}
