package azure

import (
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/compute/armcompute/v5"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/blob"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/assert"
)

func TestBlobPropertiesToOperationProgressUpdate(t *testing.T) {
	tests := []struct {
		testName       string
		blobProperties *blob.GetPropertiesResponse
		expectedOutput OperationProgressUpdate
	}{
		{
			testName:       "no status or progress data",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: nil, CopyProgress: utils.ToPtr("")},
			expectedOutput: OperationProgressUpdate{status: "", progress: ""},
		},
		{
			testName:       "unexpected status",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypeSuccess), CopyProgress: utils.ToPtr("")},
			expectedOutput: OperationProgressUpdate{status: "", progress: ""},
		},
		{
			testName:       "status data only",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: ""},
		},
		{
			testName:       "progress data in non-default format 1",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("10%")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "10%"},
		},
		{
			testName:       "progress data in non-default format 2",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("50/100/200")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "50/100/200"},
		},
		{
			testName:       "progress data is parsed correctly 1",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("50/100")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "50%, 50/100"},
		},
		{
			testName:       "progress data is parsed correctly 2",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("(15/40)")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "37%, 15/40"},
		},
		{
			testName:       "progress data is parsed correctly 3",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("(136748990464/274880004608)")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "49%, 136748990464/274880004608"},
		},
		{
			testName:       "progress data is parsed correctly 4",
			blobProperties: &blob.GetPropertiesResponse{CopyStatus: to.Ptr(blob.CopyStatusTypePending), CopyProgress: utils.ToPtr("(47972352000/274880004608)")},
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "17%, 47972352000/274880004608"},
		},
	}

	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			actualOutput := blobPropertiesToOperationProgressUpdate(test.blobProperties)
			assert.Equal(t, test.expectedOutput.status, actualOutput.status)
			assert.Equal(t, test.expectedOutput.progress, actualOutput.progress)
		})
	}
}

func TestCopyDetailsToOperationProgressUpdate(t *testing.T) {
	tests := []struct {
		testName       string
		copiedSize     int64
		copyTotalSize  int64
		expectedOutput OperationProgressUpdate
	}{
		{
			testName:       "progress 1",
			copiedSize:     50,
			copyTotalSize:  100,
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "50%, 50/100"},
		},
		{
			testName:       "progress 2",
			copiedSize:     15,
			copyTotalSize:  40,
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "37%, 15/40"},
		},
		{
			testName:       "progress 3",
			copiedSize:     136748990464,
			copyTotalSize:  274880004608,
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "49%, 136748990464/274880004608"},
		},
		{
			testName:       "progress 4",
			copiedSize:     47972352000,
			copyTotalSize:  274880004608,
			expectedOutput: OperationProgressUpdate{status: "Copying image", progress: "17%, 47972352000/274880004608"},
		},
	}

	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			actualOutput := copyDetailsToOperationProgressUpdate(test.copiedSize, test.copyTotalSize)
			assert.Equal(t, test.expectedOutput.status, actualOutput.status)
			assert.Equal(t, test.expectedOutput.progress, actualOutput.progress)
		})
	}
}

func TestGalleryImageVersionDetailsToOperationProgressUpdate(t *testing.T) {
	tests := []struct {
		testName                   string
		galleryImageVersionDetails armcompute.GalleryImageVersion
		expectedOutput             OperationProgressUpdate
	}{
		{
			testName:                   "no image version properties",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{},
			expectedOutput:             OperationProgressUpdate{status: "", progress: ""},
		},
		{
			testName: "no provisioning state",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{},
			},
			expectedOutput: OperationProgressUpdate{status: "", progress: ""},
		},
		{
			testName: "unexpected provisioning state",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Location: to.Ptr("westus"),
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateFailed),
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Provisioning image", progress: "Failed"},
		},
		{
			testName: "replication status nil",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Location: to.Ptr("westus"),
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: nil,
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Provisioning image", progress: ""},
		},
		{
			testName: "replication summary nil",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Location: to.Ptr("westus"),
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: nil,
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Provisioning image", progress: ""},
		},
		{
			testName: "replication summary is empty array",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Provisioning image", progress: ""},
		},
		{
			testName: "replication to regions - no progress yet",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateUnknown),
								Progress: to.Ptr[int32](0),
							},
							{
								Region:   to.Ptr("westus2"),
								State:    to.Ptr(armcompute.ReplicationStateUnknown),
								Progress: nil,
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "0%"},
		},
		{
			testName: "replication to regions - single region in progress",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](61),
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "61%"},
		},
		{
			testName: "replication to regions - single region completed",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](0),
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "100%"},
		},
		{
			testName: "replication to multiple regions 1",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](90),
							},
							{
								Region:   to.Ptr("westus2"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](30),
							},
							{
								Region:   to.Ptr("westus3"),
								State:    to.Ptr(armcompute.ReplicationStateUnknown),
								Progress: nil,
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "40%"},
		},
		{
			testName: "replication to multiple regions 2",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](90),
							},
							{
								Region:   to.Ptr("westus2"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](30),
							},
							{
								Region:   to.Ptr("eastus"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](15),
							},
							{
								Region:   to.Ptr("eastus2"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](70),
							},
							{
								Region:   to.Ptr("westus3"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](45),
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "50%"},
		},
		{
			testName: "replication to multiple regions 3",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](100),
							},
							{
								Region:   to.Ptr("westus2"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](0),
							},
							{
								Region:   to.Ptr("eastus"),
								State:    to.Ptr(armcompute.ReplicationStateReplicating),
								Progress: to.Ptr[int32](50),
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "83%"},
		},
		{
			testName: "replication to multiple regions - completed",
			galleryImageVersionDetails: armcompute.GalleryImageVersion{
				Properties: &armcompute.GalleryImageVersionProperties{
					ProvisioningState: to.Ptr(armcompute.GalleryProvisioningStateCreating),
					ReplicationStatus: &armcompute.ReplicationStatus{
						Summary: []*armcompute.RegionalReplicationStatus{
							{
								Region:   to.Ptr("westus"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](100),
							},
							{
								Region:   to.Ptr("westus2"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](0),
							},
							{
								Region:   to.Ptr("eastus"),
								State:    to.Ptr(armcompute.ReplicationStateCompleted),
								Progress: to.Ptr[int32](100),
							},
						},
					},
				},
			},
			expectedOutput: OperationProgressUpdate{status: "Replicating image to regions", progress: "100%"},
		},
	}

	for _, test := range tests {
		t.Run(test.testName, func(t *testing.T) {
			actualOutput := galleryImageVersionDetailsToOperationProgressUpdate(&armcompute.GalleryImageVersionsClientGetResponse{
				GalleryImageVersion: test.galleryImageVersionDetails,
			})
			assert.Equal(t, test.expectedOutput.status, actualOutput.status)
			assert.Equal(t, test.expectedOutput.progress, actualOutput.progress)
		})
	}
}
