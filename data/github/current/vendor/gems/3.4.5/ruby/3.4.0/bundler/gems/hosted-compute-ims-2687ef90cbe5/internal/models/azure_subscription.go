package models

import "time"

type AzureSubscription struct {
	Id                 uint64
	SubscriptionId     string
	ImageType          ImageType
	ResourcesPrefix    string
	CreatedAt          time.Time
	UpdatedAt          *time.Time
	ImageVersionsCount uint
	ImageVersionsLimit uint
}

// AzureSubscriptionUpsert is used to create or update an Azure subscription.
// It contains the fields which can be upserted only to avoid overwriting fields that are not meant to be updated manually
// such as IMageVersionsCount, CreatedAt and UpdatedAt
type AzureSubscriptionUpsert struct {
	SubscriptionId     string
	ImageType          ImageType
	ResourcesPrefix    string
	ImageVersionsLimit uint
}
