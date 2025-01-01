package azure

import (
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
)

type OperationProgressUpdate struct {
	status   string
	progress string
}

func (p OperationProgressUpdate) String() string {
	if p.progress != "" {
		return fmt.Sprintf("%s (%s)", p.status, p.progress)
	}

	return p.status
}

func blobPropertiesToOperationProgressUpdate(blobProps *blob.GetPropertiesResponse) OperationProgressUpdate {
	if blobProps.CopyStatus == nil {
		return OperationProgressUpdate{}
	}

	if *blobProps.CopyStatus != blob.CopyStatusTypePending {
		return OperationProgressUpdate{}
	}

	if blobProps.CopyProgress == nil {
		return OperationProgressUpdate{status: "Copying image"}
	}

	// Parse '(136748990464/274880004608)' string to more readable view with % value: '(49%, 136748990464/274880004608)'
	progressParts := strings.Split(*blobProps.CopyProgress, "/")
	if len(progressParts) == 2 {
		currentProgress, parseErr1 := strconv.Atoi(strings.TrimLeft(progressParts[0], "("))
		maxProgress, parseErr2 := strconv.Atoi(strings.TrimRight(progressParts[1], ")"))
		if parseErr1 == nil && parseErr2 == nil {
			percentProgress := currentProgress * 100 / maxProgress
			return OperationProgressUpdate{
				status:   "Copying image",
				progress: fmt.Sprintf("%d%%, %d/%d", percentProgress, currentProgress, maxProgress),
			}
		}
	}

	return OperationProgressUpdate{status: "Copying image", progress: *blobProps.CopyProgress}
}

func copyDetailsToOperationProgressUpdate(copiedSize, copyTotalSize int64) OperationProgressUpdate {
	progressPercent := copiedSize * 100 / copyTotalSize

	return OperationProgressUpdate{
		status:   "Copying image",
		progress: fmt.Sprintf("%d%%, %d/%d", progressPercent, copiedSize, copyTotalSize),
	}
}

func galleryImageVersionDetailsToOperationProgressUpdate(galleryImageVersionDetails *armcompute.GalleryImageVersionsClientGetResponse) OperationProgressUpdate {
	props := galleryImageVersionDetails.Properties

	if props == nil || props.ProvisioningState == nil {
		return OperationProgressUpdate{}
	}

	if *props.ProvisioningState != armcompute.GalleryProvisioningStateCreating {
		return OperationProgressUpdate{status: "Provisioning image", progress: string(*props.ProvisioningState)}
	}

	if props.ReplicationStatus == nil || props.ReplicationStatus.Summary == nil || len(props.ReplicationStatus.Summary) == 0 {
		return OperationProgressUpdate{status: "Provisioning image"}
	}

	var regionsPercentCompleted int32 = 0
	for _, regionStatus := range props.ReplicationStatus.Summary {
		if regionStatus.State == nil {
			continue
		}

		if *regionStatus.State == armcompute.ReplicationStateCompleted {
			// if region is fully completed, track it as 100%
			regionsPercentCompleted += 100
			continue
		}

		if regionStatus.Progress != nil {
			regionsPercentCompleted += *regionStatus.Progress
		}
	}

	totalPercent := math.Floor(float64(regionsPercentCompleted) / float64(len(props.ReplicationStatus.Summary)))
	return OperationProgressUpdate{status: "Replicating image to regions", progress: fmt.Sprintf("%.0f%%", totalPercent)}
}
