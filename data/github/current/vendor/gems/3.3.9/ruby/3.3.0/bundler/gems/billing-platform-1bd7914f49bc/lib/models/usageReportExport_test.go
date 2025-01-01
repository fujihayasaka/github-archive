package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

func Test_NewPendingUsageReportExport(t *testing.T) {
	input := &proto.QueueUsageReportExportRequest{
		CustomerId:      "1",
		ActorId:         2,
		OrganizationIds: []int64{3, 4},
		StartDate:       time.Now().Unix(),
		EndDate:         time.Now().Unix(),
		LegacyReport:    false,
		IsStafftools:    true,
	}

	usageReportExport := NewPendingUsageReportExport(input)

	assert.Equal(t, usageReportExport.PartitionKey, UsageReportExportsActivePK)
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusPending)
	assert.Equal(t, usageReportExport.CustomerID, input.CustomerId)
	assert.Equal(t, usageReportExport.ActorId, input.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, input.OrganizationIds)
	assert.Equal(t, usageReportExport.StartDate, time.Unix(input.StartDate, 0))
	assert.Equal(t, usageReportExport.EndDate, time.Unix(input.EndDate, 0))
	assert.Equal(t, usageReportExport.LegacyReport, input.LegacyReport, false)
	assert.Equal(t, usageReportExport.IsStafftools, input.IsStafftools)

	// we don't set these fields for pending vNext usage report exports
	assert.Equal(t, usageReportExport.ExportOperationUUID, "")
	assert.Equal(t, len(usageReportExport.ExportBlobs), 0)
	assert.Equal(t, usageReportExport.BillableOwnerID, int64(0))
	assert.Equal(t, usageReportExport.BillableOwnerType, proto.BillableOwnerType_Unspecified)
}

func Test_NewPendingLegacyUsageReportExport(t *testing.T) {
	input := &proto.QueueUsageReportExportRequest{
		CustomerId:        "1",
		ActorId:           2,
		OrganizationIds:   []int64{3, 4},
		StartDate:         time.Now().Unix(),
		EndDate:           time.Now().Unix(),
		LegacyReport:      true,
		BillableOwnerType: proto.BillableOwnerType_Business,
		BillableOwnerId:   int64(5),
	}

	usageReportExport := NewPendingUsageReportExport(input)

	assert.Equal(t, usageReportExport.PartitionKey, UsageReportExportsActivePK)
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusPending)
	assert.Equal(t, usageReportExport.CustomerID, input.CustomerId)
	assert.Equal(t, usageReportExport.ActorId, input.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, input.OrganizationIds)
	assert.Equal(t, usageReportExport.StartDate, time.Unix(input.StartDate, 0))
	assert.Equal(t, usageReportExport.EndDate, time.Unix(input.EndDate, 0))
	assert.Equal(t, usageReportExport.LegacyReport, input.LegacyReport, true)
	assert.Equal(t, usageReportExport.BillableOwnerType, input.BillableOwnerType, proto.BillableOwnerType_Business)
	assert.Equal(t, usageReportExport.BillableOwnerID, input.BillableOwnerId, 5)

	// we don't set these fields for pending usage report exports
	assert.Equal(t, usageReportExport.ExportOperationUUID, "")
	assert.Equal(t, len(usageReportExport.ExportBlobs), 0)
}

func Test_NewFailedUsageReportExport(t *testing.T) {
	inputUsageReportExport := &UsageReportExport{
		Key: Key{
			Id: "test-id",
		},
		CustomerID:          "1",
		ActorId:             2,
		OrganizationIDs:     []int64{3, 4},
		StartDate:           time.Now(),
		EndDate:             time.Now(),
		LegacyReport:        false,
		ExportOperationUUID: "test-uuid",
		IsStafftools:        true,
	}

	usageReportExport := NewFailedUsageReportExport(inputUsageReportExport)

	assert.Equal(t, usageReportExport.PartitionKey, fmt.Sprintf("customer:%s:usageReportExports:failed", inputUsageReportExport.CustomerID))
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusFailed)
	assert.Equal(t, usageReportExport.CustomerID, inputUsageReportExport.CustomerID)
	assert.Equal(t, usageReportExport.ActorId, inputUsageReportExport.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, inputUsageReportExport.OrganizationIDs)
	assert.Equal(t, usageReportExport.StartDate, inputUsageReportExport.StartDate)
	assert.Equal(t, usageReportExport.EndDate, inputUsageReportExport.EndDate)
	assert.Equal(t, usageReportExport.LegacyReport, inputUsageReportExport.LegacyReport)
	assert.Equal(t, usageReportExport.ExportOperationUUID, inputUsageReportExport.ExportOperationUUID)
	assert.Equal(t, usageReportExport.IsStafftools, inputUsageReportExport.IsStafftools)

	// we don't set this field for failed vNext usage report exports
	assert.Equal(t, len(usageReportExport.ExportBlobs), 0)
	assert.Equal(t, usageReportExport.BillableOwnerID, int64(0))
	assert.Equal(t, usageReportExport.BillableOwnerType, proto.BillableOwnerType_Unspecified)
}

func Test_NewFaileLegacyUsageReportExport(t *testing.T) {
	inputUsageReportExport := &UsageReportExport{
		Key: Key{
			Id: "test-id",
		},
		CustomerID:          "1",
		ActorId:             2,
		OrganizationIDs:     []int64{3, 4},
		StartDate:           time.Now(),
		EndDate:             time.Now(),
		LegacyReport:        true,
		ExportOperationUUID: "test-uuid",
		BillableOwnerType:   proto.BillableOwnerType_Business,
		BillableOwnerID:     5,
	}

	usageReportExport := NewFailedUsageReportExport(inputUsageReportExport)

	assert.Equal(t, usageReportExport.PartitionKey, fmt.Sprintf("customer:%s:usageReportExports:failed", inputUsageReportExport.CustomerID))
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusFailed)
	assert.Equal(t, usageReportExport.CustomerID, inputUsageReportExport.CustomerID)
	assert.Equal(t, usageReportExport.ActorId, inputUsageReportExport.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, inputUsageReportExport.OrganizationIDs)
	assert.Equal(t, usageReportExport.StartDate, inputUsageReportExport.StartDate)
	assert.Equal(t, usageReportExport.EndDate, inputUsageReportExport.EndDate)
	assert.Equal(t, usageReportExport.LegacyReport, inputUsageReportExport.LegacyReport)
	assert.Equal(t, usageReportExport.ExportOperationUUID, inputUsageReportExport.ExportOperationUUID)
	assert.Equal(t, usageReportExport.BillableOwnerType, inputUsageReportExport.BillableOwnerType, proto.BillableOwnerType_Business)
	assert.Equal(t, usageReportExport.BillableOwnerID, inputUsageReportExport.BillableOwnerID, 5)

	// we don't set this field for failed usage report exports
	assert.Equal(t, len(usageReportExport.ExportBlobs), 0)
}

func Test_NewCompletedUsageReportExport(t *testing.T) {
	inputUsageReportExport := &UsageReportExport{
		Key: Key{
			Id: "test-id",
		},
		CustomerID:          "1",
		ActorId:             2,
		OrganizationIDs:     []int64{3, 4},
		StartDate:           time.Now(),
		EndDate:             time.Now(),
		LegacyReport:        false,
		ExportOperationUUID: "test-uuid",
		ExportBlobs:         []string{"test-blob-1", "test-blob-2"},
		IsStafftools:        true,
	}

	usageReportExport := NewCompletedUsageReportExport(inputUsageReportExport)

	assert.Equal(t, usageReportExport.PartitionKey, fmt.Sprintf("customer:%s:usageReportExports:completed", inputUsageReportExport.CustomerID))
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusCompleted)
	assert.Equal(t, usageReportExport.CustomerID, inputUsageReportExport.CustomerID)
	assert.Equal(t, usageReportExport.ActorId, inputUsageReportExport.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, inputUsageReportExport.OrganizationIDs)
	assert.Equal(t, usageReportExport.StartDate, inputUsageReportExport.StartDate)
	assert.Equal(t, usageReportExport.EndDate, inputUsageReportExport.EndDate)
	assert.Equal(t, usageReportExport.LegacyReport, inputUsageReportExport.LegacyReport)
	assert.Equal(t, usageReportExport.ExportOperationUUID, inputUsageReportExport.ExportOperationUUID)
	assert.Equal(t, usageReportExport.ExportBlobs, inputUsageReportExport.ExportBlobs)
	assert.Equal(t, usageReportExport.IsStafftools, inputUsageReportExport.IsStafftools)

	// we don't set this field for completed usage report exports
	assert.Equal(t, usageReportExport.BillableOwnerID, int64(0))
	assert.Equal(t, usageReportExport.BillableOwnerType, proto.BillableOwnerType_Unspecified)
}

func Test_NewCompletedLegacyUsageReportExport(t *testing.T) {
	inputUsageReportExport := &UsageReportExport{
		Key: Key{
			Id: "test-id",
		},
		CustomerID:          "1",
		ActorId:             2,
		OrganizationIDs:     []int64{3, 4},
		StartDate:           time.Now(),
		EndDate:             time.Now(),
		LegacyReport:        false,
		ExportOperationUUID: "test-uuid",
		ExportBlobs:         []string{"test-blob-1", "test-blob-2"},
		BillableOwnerType:   proto.BillableOwnerType_Business,
		BillableOwnerID:     5,
	}

	usageReportExport := NewCompletedUsageReportExport(inputUsageReportExport)

	assert.Equal(t, usageReportExport.PartitionKey, fmt.Sprintf("customer:%s:usageReportExports:completed", inputUsageReportExport.CustomerID))
	assert.Equal(t, usageReportExport.Status, UsageReportExportStatusCompleted)
	assert.Equal(t, usageReportExport.CustomerID, inputUsageReportExport.CustomerID)
	assert.Equal(t, usageReportExport.ActorId, inputUsageReportExport.ActorId)
	assert.Equal(t, usageReportExport.OrganizationIDs, inputUsageReportExport.OrganizationIDs)
	assert.Equal(t, usageReportExport.StartDate, inputUsageReportExport.StartDate)
	assert.Equal(t, usageReportExport.EndDate, inputUsageReportExport.EndDate)
	assert.Equal(t, usageReportExport.LegacyReport, inputUsageReportExport.LegacyReport)
	assert.Equal(t, usageReportExport.ExportOperationUUID, inputUsageReportExport.ExportOperationUUID)
	assert.Equal(t, usageReportExport.ExportBlobs, inputUsageReportExport.ExportBlobs)
	assert.Equal(t, usageReportExport.BillableOwnerType, inputUsageReportExport.BillableOwnerType, proto.BillableOwnerType_Business)
	assert.Equal(t, usageReportExport.BillableOwnerID, inputUsageReportExport.BillableOwnerID, 5)
}
