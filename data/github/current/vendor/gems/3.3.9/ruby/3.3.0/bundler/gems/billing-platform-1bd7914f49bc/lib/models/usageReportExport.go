package models

import (
	"fmt"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
)

type UsageReportStatus string

const (
	UsageReportExportStatusPending   UsageReportStatus = "pending"
	UsageReportExportStatusLoading   UsageReportStatus = "loading"
	UsageReportExportStatusFailed    UsageReportStatus = "failed"
	UsageReportExportStatusCompleted UsageReportStatus = "completed"
)

const (
	UsageReportExportsActivePK = "usageReportExports:active"
)

type UsageReportExport struct {
	Key
	CustomerID   string
	ActorId      int64
	StartDate    time.Time
	EndDate      time.Time
	Status       UsageReportStatus
	ReceivedAt   time.Time
	LegacyReport bool
	IsStafftools bool

	// (optional) for org admin requests, represents the org IDs the requester is
	// an admin of to filter usage report exports for. A user can be org admin of
	// more than one org in an enterprise which is why this is an array
	OrganizationIDs     []int64  `json:",omitempty"`
	ExportOperationUUID string   `json:",omitempty"`
	ExportBlobs         []string `json:",omitempty"`

	// (Optional) for legacy reports. These parameters help a simpler and more efficient
	// query for our legacy kusto exports
	BillableOwnerType proto.BillableOwnerType `json:",omitempty"`
	BillableOwnerID   int64                   `json:",omitempty"`
}

func NewActiveUsageReportKey(customerID string, actorID int64) *Key {
	return &Key{
		PartitionKey: UsageReportExportsActivePK,
		Id:           buildActiveUsageReportExportId(customerID, actorID),
	}
}

func NewCompletedUsageReportKey(usageReportExport *UsageReportExport) *Key {
	return &Key{
		PartitionKey: fmt.Sprintf("customer:%s:usageReportExports:completed", usageReportExport.CustomerID),
		Id:           usageReportExport.ExportOperationUUID,
	}
}

func NewFailedUsageReportKey(usageReportExport *UsageReportExport) *Key {
	return &Key{
		PartitionKey: fmt.Sprintf("customer:%s:usageReportExports:failed", usageReportExport.CustomerID),
		Id:           usageReportExport.ExportOperationUUID,
	}
}

func NewPendingUsageReportExport(input *proto.QueueUsageReportExportRequest) *UsageReportExport {
	startDate := time.Unix(input.StartDate, 0)
	endDate := time.Unix(input.EndDate, 0)

	return &UsageReportExport{
		Key: Key{
			PartitionKey: UsageReportExportsActivePK,
			Id:           buildActiveUsageReportExportId(input.CustomerId, input.ActorId),
		},

		CustomerID:        input.CustomerId,
		ActorId:           input.ActorId,
		OrganizationIDs:   input.OrganizationIds,
		StartDate:         startDate,
		EndDate:           endDate,
		Status:            UsageReportExportStatusPending,
		LegacyReport:      input.LegacyReport,
		ReceivedAt:        time.Now().UTC(),
		BillableOwnerType: input.BillableOwnerType,
		BillableOwnerID:   input.BillableOwnerId,
		IsStafftools:      input.IsStafftools,
	}
}

func NewFailedUsageReportExport(usageReportExport *UsageReportExport) *UsageReportExport {
	return &UsageReportExport{
		Key: Key{
			PartitionKey: fmt.Sprintf("customer:%s:usageReportExports:failed", usageReportExport.CustomerID),
			// use the export operation UUID as the ID for completed usage report exports
			Id: usageReportExport.ExportOperationUUID,
		},
		CustomerID:          usageReportExport.CustomerID,
		ActorId:             usageReportExport.ActorId,
		OrganizationIDs:     usageReportExport.OrganizationIDs,
		StartDate:           usageReportExport.StartDate,
		EndDate:             usageReportExport.EndDate,
		Status:              UsageReportExportStatusFailed,
		LegacyReport:        usageReportExport.LegacyReport,
		ExportOperationUUID: usageReportExport.ExportOperationUUID,
		ReceivedAt:          usageReportExport.ReceivedAt,
		BillableOwnerType:   usageReportExport.BillableOwnerType,
		BillableOwnerID:     usageReportExport.BillableOwnerID,
		IsStafftools:        usageReportExport.IsStafftools,
	}
}

func NewCompletedUsageReportExport(usageReportExport *UsageReportExport) *UsageReportExport {
	return &UsageReportExport{
		Key: Key{
			PartitionKey: fmt.Sprintf("customer:%s:usageReportExports:completed", usageReportExport.CustomerID),
			// use the export operation UUID as the ID for completed usage report exports
			Id: usageReportExport.ExportOperationUUID,
		},
		CustomerID:          usageReportExport.CustomerID,
		ActorId:             usageReportExport.ActorId,
		OrganizationIDs:     usageReportExport.OrganizationIDs,
		StartDate:           usageReportExport.StartDate,
		EndDate:             usageReportExport.EndDate,
		Status:              UsageReportExportStatusCompleted,
		LegacyReport:        usageReportExport.LegacyReport,
		ExportOperationUUID: usageReportExport.ExportOperationUUID,
		ExportBlobs:         usageReportExport.ExportBlobs,
		ReceivedAt:          usageReportExport.ReceivedAt,
		BillableOwnerType:   usageReportExport.BillableOwnerType,
		BillableOwnerID:     usageReportExport.BillableOwnerID,
		IsStafftools:        usageReportExport.IsStafftools,
	}
}

func buildActiveUsageReportExportId(customerID string, actorID int64) string {
	// we use the actor ID to ensure that the same actor can't queue up multiple reports for the same customer
	return fmt.Sprintf(`customer:%s:actor:%d`, customerID, actorID)
}
