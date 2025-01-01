package models

import (
	"fmt"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/data/aztables"
	"github.com/github/billing-platform/lib/twirp/proto"
)

type AzureEmissionStatus byte

const (
	AzureEmissionNew AzureEmissionStatus = iota
	AzureEmissionRecorded
	AzureEmissionCompleted
	AzureEmissionFailed
	AzureEmissionIgnored
)

type AzureEmissionPartitionDetail struct {
	CustomerId string
	Sku        string
	Year       int64
	Month      int64
	Day        int64
}

type AzureEmission struct {
	*Key
	AzurePartitionKey string
	MeterId           string
	SubscriptionId    string
	Quantity          float64
	Status            AzureEmissionStatus
	ErrorMessage      string
	GrossQuantity     float64
}

type UsageEntity struct {
	UsageEntityId string
	Name          string
	IsCostCenter  bool
}

type AzureEmissionRecord struct {
	AzureEmission
	UsageEntity           UsageEntity
	EstimatedBilledAmount float64
	FriendlySkuName       string
}

type AzureEmissionsPartitionDetail struct {
	Sku   string
	Year  int64
	Month int64
	Day   int64
}

func NewAzureEmissionKey(apd *AzureEmissionPartitionDetail) *Key {
	partitionKey := GetAzureEmissionsPartitionKey(apd)
	return &Key{
		PartitionKey: fmt.Sprintf("%s:%d:%d", partitionKey, apd.Year, apd.Month),
		Id:           fmt.Sprintf("%s:%d:%d:%d", partitionKey, apd.Year, apd.Month, apd.Day),
	}
}

func NewAzureEmission(apd *AzureEmissionPartitionDetail, usageItem aztables.EDMEntity, discountQuantity float64) *AzureEmission {
	azureEmission := &AzureEmission{
		Key:               NewAzureEmissionKey(apd),
		AzurePartitionKey: usageItem.PartitionKey,
		MeterId:           usageItem.Properties["MeterId"].(string),
		SubscriptionId:    usageItem.Properties["SubscriptionId"].(string),
		Quantity:          usageItem.Properties["Quantity"].(float64),
		Status:            AzureEmissionNew,
		GrossQuantity:     usageItem.Properties["Quantity"].(float64) + discountQuantity,
	}

	return azureEmission
}

func GetAzureEmissionsPartitionKey(apd *AzureEmissionPartitionDetail) string {
	return fmt.Sprintf("%s:%s:azureEmission", apd.CustomerId, apd.Sku)
}

func (a *AzureEmissionRecord) ToProto() *proto.AzureEmission {
	return &proto.AzureEmission{
		AzurePartitionKey: a.AzurePartitionKey,
		Sku:               strings.Split(a.Key.PartitionKey, ":")[1], // Get Sku from partition key
		FriendlySkuName:   a.FriendlySkuName,
		MeterId:           a.MeterId,
		SubscriptionId:    a.SubscriptionId,
		Quantity:          a.Quantity,
		Status:            a.Status.ToProto(),
		ErrorMessage:      a.ErrorMessage,
		GrossQuantity:     a.GrossQuantity,
		UsageEntity: &proto.UsageEntity{
			UsageEntityId: a.UsageEntity.UsageEntityId,
			Name:          a.UsageEntity.Name,
			IsCostCenter:  a.UsageEntity.IsCostCenter,
		},
		EstimatedBilledAmount: a.EstimatedBilledAmount,
	}
}

func (a *AzureEmission) ToProto() *proto.AzureEmission {
	return &proto.AzureEmission{
		AzurePartitionKey: a.AzurePartitionKey,
		Sku:               strings.Split(a.Key.PartitionKey, ":")[1], // Extra sku from partition key
		MeterId:           a.MeterId,
		SubscriptionId:    a.SubscriptionId,
		Quantity:          a.Quantity,
		Status:            a.Status.ToProto(),
		ErrorMessage:      a.ErrorMessage,
		GrossQuantity:     a.GrossQuantity,
	}
}

func (s AzureEmissionStatus) ToProto() proto.AzureEmissionStatus {
	return proto.AzureEmissionStatus(s)
}

func (s AzureEmissionStatus) GetStatusString() string {
	switch s {
	case AzureEmissionNew:
		return "New"
	case AzureEmissionRecorded:
		return "Recorded"
	case AzureEmissionCompleted:
		return "Completed"
	case AzureEmissionFailed:
		return "Failed"
	case AzureEmissionIgnored:
		return "Ignored"
	default:
		return "Unknown"
	}
}
