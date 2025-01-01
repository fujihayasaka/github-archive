// Package models contains the data models for the licensify service.
package models

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/kvp"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
)

// Now is the UTC time used for caculating time left this month
var Now = time.Now

// EndOfMonth returns the last moment of the current month in Unix time
func EndOfMonth() int64 {
	now := Now().UTC()
	// Find the start of the next month.
	year, month, _ := now.Date()
	nextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, now.Location())

	// Calculate the last moment of the current month
	endOfMonth := nextMonth.Add(-time.Second)

	return endOfMonth.Unix()
}

// RemainingSecondsThisMonth returns the number of seconds remaining in the month for a given time.
func RemainingSecondsThisMonth() *int64 {
	now := Now().UTC()

	// Find the start of the next month.
	year, month, _ := now.Date()
	nextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, now.Location())

	// Subtract now from the start of the next month.
	remainingSeconds := int64(nextMonth.Sub(now).Seconds())
	return &remainingSeconds
}

// Key is a wrapper around the partition key and ID of a document.
type Key struct {
	PartitionKey string `json:"partitionKey"`
	ID           string `json:"id"`
}

// GetLoggerFields gets logger fields for key
func (key *Key) GetLoggerFields() []kvp.Field {
	return []kvp.Field{
		kvp.String("db.cosmosdb.partition_key", key.PartitionKey),
		kvp.String("db.cosmosdb.document_id", key.ID),
	}
}

// CosmosProperties represents the properties of a Cosmos document.
type CosmosProperties struct {
	ETag      *azcore.ETag `json:"_etag"`
	TTL       *int64       `json:"ttl,omitempty"` // Time to live in seconds. If not specified or -1, the document will never expire.
	Timestamp int64        `json:"_ts"`
}

// IsNewDocument returns true if the model has not been saved to Cosmos.
func (cp CosmosProperties) IsNewDocument() bool {
	return cp.Timestamp == 0
}

// Product represents a GitHub product.
type Product byte

// Product constants.
const (
	ProductUnspecified Product = iota
	ProductGhas
	ProductSDLC // SDLC licenses can be consumed by enterprises paying for GHE or organizations on the Team plan.
)

var (
	productToString = map[Product]string{
		ProductGhas: "ghas",
		ProductSDLC: "sdlc",
	}
	stringToProduct = map[string]Product{
		"ghas": ProductGhas,
		"sdlc": ProductSDLC,
	}
)

// String returns the string representation of the Product.
func (p Product) String() string {
	return productToString[p]
}

// MarshalJSON marshals the Product to a JSON string.
func (p Product) MarshalJSON() ([]byte, error) {
	return json.Marshal(p.String())
}

// UnmarshalJSON unmarshals the Product from a JSON string.
func (p *Product) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	value, ok := stringToProduct[s]
	if !ok {
		return fmt.Errorf("invalid Product: %s", s)
	}
	*p = value
	return nil
}

// ToProto converts the Product to a proto.Product.
func (p Product) ToProto() proto.Product {
	return proto.Product(p)
}

// ProductEnablementType represents the type of a product enablement target.
type ProductEnablementType byte

// ProductEnablementType constants.
const (
	ProductEnablementTypeUnspecified ProductEnablementType = iota
	ProductEnablementTypeOrg
	ProductEnablementTypeRepo
	ProductEnablementTypeEnterpriseServer
)

var (
	productEnablementTypeToString = map[ProductEnablementType]string{
		ProductEnablementTypeOrg:              "org",
		ProductEnablementTypeRepo:             "repo",
		ProductEnablementTypeEnterpriseServer: "enterpriseServer",
	}
	stringToProductEnablementType = map[string]ProductEnablementType{
		"org":              ProductEnablementTypeOrg,
		"repo":             ProductEnablementTypeRepo,
		"enterpriseServer": ProductEnablementTypeEnterpriseServer,
	}
)

// String returns the string representation of the ProductEnablementType.
func (p ProductEnablementType) String() string {
	return productEnablementTypeToString[p]
}

// MarshalJSON marshals the ProductEnablementType to a JSON string.
func (p ProductEnablementType) MarshalJSON() ([]byte, error) {
	return json.Marshal(p.String())
}

// UnmarshalJSON unmarshals the ProductEnablementType from a JSON string.
func (p *ProductEnablementType) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	value, ok := stringToProductEnablementType[s]
	if !ok {
		return fmt.Errorf("invalid ProductEnablementType: %s", s)
	}
	*p = value
	return nil
}

// ToProto converts the ProductEnablementType to a proto.ProductEnablementType.
func (p ProductEnablementType) ToProto() proto.ProductEnablementType {
	return proto.ProductEnablementType(p)
}

// SdlcLicensingModel represents if a customer is metered or volume licensed
type SdlcLicensingModel byte

// SdlcLicensingModel constants.
const (
	LicensingModelUnspecified SdlcLicensingModel = iota
	LicensingModelMetered
	LicensingModelVolume
)

var (
	licensingModelToString = map[SdlcLicensingModel]string{
		LicensingModelMetered: "METERED",
		LicensingModelVolume:  "VOLUME",
	}
	stringToLicensingModel = map[string]SdlcLicensingModel{
		"METERED": LicensingModelMetered,
		"VOLUME":  LicensingModelVolume,
	}
)

// String returns the string representation of the SdlcLicensingModel.
func (sdlcLicensingModel SdlcLicensingModel) String() string {
	return licensingModelToString[sdlcLicensingModel]
}

// MarshalJSON marshals the SdlcLicensingModel to a JSON string.
func (sdlcLicensingModel SdlcLicensingModel) MarshalJSON() ([]byte, error) {
	return json.Marshal(sdlcLicensingModel.String())
}

// UnmarshalJSON unmarshals the SdlcLicensingModel from a JSON string.
func (sdlcLicensingModel *SdlcLicensingModel) UnmarshalJSON(b []byte) error {
	var licensingModelString string
	if err := json.Unmarshal(b, &licensingModelString); err != nil {
		return err
	}
	value, ok := stringToLicensingModel[licensingModelString]
	if !ok {
		return fmt.Errorf("invalid licensing model: %s", licensingModelString)
	}
	*sdlcLicensingModel = value
	return nil
}

// ToProto converts the SdlcLicensingModel to a proto.LicensingModel.
func (sdlcLicensingModel SdlcLicensingModel) ToProto() proto.LicensingModel {
	return proto.LicensingModel(sdlcLicensingModel)
}

// LicenseStatus represents whether a license is active, or deactivated but still billed for
type LicenseStatus byte

// LicenseStatus constants.
const (
	LicenseStatusUnspecified LicenseStatus = iota
	LicenseStatusActive
	LicenseStatusDeactivated
	LicenseStatusSuspended
)

var (
	statusToString = map[LicenseStatus]string{
		LicenseStatusUnspecified: "",
		LicenseStatusActive:      "active",
		LicenseStatusDeactivated: "deactivated",
		LicenseStatusSuspended:   "suspended",
	}
	stringToStatus = map[string]LicenseStatus{
		"":            LicenseStatusUnspecified,
		"active":      LicenseStatusActive,
		"deactivated": LicenseStatusDeactivated,
		"suspended":   LicenseStatusSuspended,
	}
)

// String returns the string representation of the Status.
func (status LicenseStatus) String() string {
	return statusToString[status]
}

// MarshalJSON marshals the Status to a JSON string.
func (status LicenseStatus) MarshalJSON() ([]byte, error) {
	return json.Marshal(status.String())
}

// UnmarshalJSON unmarshals the Status from a JSON string.
func (status *LicenseStatus) UnmarshalJSON(b []byte) error {
	var statusString string
	if err := json.Unmarshal(b, &statusString); err != nil {
		return err
	}
	value, ok := stringToStatus[statusString]
	if !ok {
		return fmt.Errorf("invalid Status: %s", statusString)
	}
	*status = value
	return nil
}

// ToProto converts the Status to a proto.LicenseStatus.
func (status LicenseStatus) ToProto() proto.LicenseStatus {
	return proto.LicenseStatus(status)
}
