package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/zuora"
)

// ZuoraEmissionRollup represents the Zuora emission rollup model
type ZuoraEmissionRollup struct {
	CustomerID   string
	ProductSKU   string
	Year         int
	Month        int
	Day          int
	PartitionKey string
	ID           string
}

type ZuoraEmissionBatch struct {
	*Key
	UploadUsageRecords []zuora.UploadUsageRecord `json:"uploadUsageRecords"`
}

type BatchStatus string

const (
	BatchStatusBuilding      BatchStatus = "building"
	BatchStatusReadyToSubmit BatchStatus = "ready_to_submit"
	BatchStatusSubmitted     BatchStatus = "submitted"
	BatchStatusFailed        BatchStatus = "failed"
)

type ZuoraEmissionBatchStatus struct {
	*Key
	BatchNumber      int         `json:"batchNumber"`
	TotalRecordCount int         `json:"totalRecordCount"`
	PayloadSize      int64       `json:"payloadSize"`
	Status           BatchStatus `json:"status"`
}

type ZuoraEmissionBatchPartitionDetail struct {
	Year        int
	Month       int
	Day         int
	BatchNumber int
	CustomerId  string
}

type ZuoraEmissionBatchStatusPartitionDetail struct {
	Year        int
	Month       int
	Day         int
	BatchNumber int
}

func (s BatchStatus) IsValid() bool {
	switch s {
	case BatchStatusBuilding, BatchStatusReadyToSubmit:
		return true
	}
	return false
}

type RunType string

const (
	RunTypeNormal RunType = "normal"
	RunTypeFinal  RunType = "final"
)

type ZuoraBatchEmissionPayload struct {
	Year        int `json:"year"`
	Month       int `json:"month"`
	Day         int `json:"day"`
	BatchNumber int `json:"batchNumber"`
}

// Zuora Emission Batch Status

func NewZuoraEmissionBatchStatus(year, month, day int, batchNumber int) *ZuoraEmissionBatchStatus {
	partitionKey := GetZuoraEmissionBatchStatusKey(year, month, day)
	id := fmt.Sprintf("%s:%d", partitionKey, batchNumber)
	return &ZuoraEmissionBatchStatus{
		Key: &Key{
			PartitionKey: partitionKey,
			Id:           id,
		},
		BatchNumber:      batchNumber,
		Status:           BatchStatusBuilding,
		PayloadSize:      0,
		TotalRecordCount: 0,
	}
}

func GetZuoraEmissionBatchStatusKey(year, month, day int) string {
	return fmt.Sprintf("zuoraEmissionBatchStatus:%d:%d:%d", year, month, day)
}

func GetPartitionDetailForZuoraEmissionBatchStatus(year, month, day int) *ZuoraEmissionBatchStatusPartitionDetail {
	return &ZuoraEmissionBatchStatusPartitionDetail{
		Year:        year,
		Month:       month,
		Day:         day,
		BatchNumber: 1, // Default batch number
	}
}

func (z *ZuoraEmissionBatchStatusPartitionDetail) ToGetPartitionKey() string {
	return fmt.Sprintf("zuoraEmissionBatchStatus:%d:%d:%d", z.Year, z.Month, z.Day)
}

// Zuora Emission Batch

func NewZuoraEmissionBatch(year, month, day, batchNumber int, customerId string) *ZuoraEmissionBatch {
	partitionKey := GetZuoraEmissionBatchPartitionKey(year, month, day, batchNumber)
	id := fmt.Sprintf("customer:%s", customerId)
	return &ZuoraEmissionBatch{
		Key: &Key{
			PartitionKey: partitionKey,
			Id:           id,
		},
		UploadUsageRecords: []zuora.UploadUsageRecord{},
	}
}

func NewZuoraEmissionBatchPartitionDetail(year, month, day, batchNumber int, customerId string) *ZuoraEmissionBatchPartitionDetail {
	return &ZuoraEmissionBatchPartitionDetail{
		Year:        year,
		Month:       month,
		Day:         day,
		BatchNumber: batchNumber,
		CustomerId:  customerId,
	}
}

func GetPartitionDetailForEmissionBatch(year, month, day int, batchnumber int, customer string) *ZuoraEmissionBatchPartitionDetail {
	return &ZuoraEmissionBatchPartitionDetail{
		Year:        year,
		Month:       month,
		Day:         day,
		BatchNumber: batchnumber,
		CustomerId:  customer,
	}
}

// GetZuoraEmissionBatchPartitionKey generates the partition key for Zuora emission batch
func GetZuoraEmissionBatchPartitionKey(year, month, day, batchNumber int) string {
	return fmt.Sprintf("zuoraEmissionBatch:%d:%d:%d:batch-%d", year, month, day, batchNumber)
}

func (z *ZuoraEmissionBatchPartitionDetail) GetBatchPartitionKey() string {
	return fmt.Sprintf("zuoraEmissionBatch:%d:%d:%d:batch-%d", z.Year, z.Month, z.Day, z.BatchNumber)
}

func (z *ZuoraEmissionBatchPartitionDetail) GetID() string {
	return fmt.Sprintf("customer:%s", z.CustomerId)
}

//  Daily Zuora Emission

func GetPartitionDetailForDailyZuoraEmission(sku string, usageDate *EmissionTarget) *UsagePartitionDetail {
	activeType := Daily
	usageTime := NewUsageTime().WithYear(usageDate.Year).WithMonthInt(usageDate.Month).WithDay(int(usageDate.Day))

	return &UsagePartitionDetail{
		UsageTime:  usageTime,
		ActiveType: activeType,
		Sku:        sku,
	}
}

func GetZuoraEmissonBatchPayload(year, month, day int, batchnumber int) *ZuoraBatchEmissionPayload {
	return &ZuoraBatchEmissionPayload{
		Year:        year,
		Month:       month,
		Day:         day,
		BatchNumber: batchnumber,
	}
}
