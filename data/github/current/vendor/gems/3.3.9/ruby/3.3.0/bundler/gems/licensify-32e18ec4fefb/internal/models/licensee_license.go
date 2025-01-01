package models

import (
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// LicenseeLicense represents a customer license from the licensee's perspective.
type LicenseeLicense struct {
	*Key
	CosmosProperties
	Licensee      *Licensee
	Product       Product
	LicenseStatus LicenseStatus
	CustomerID    uint64
	ExpiresAt     int64
	SuspendedAt   *int64
}

// NewLicenseeLicense creates a new LicenseeLicense struct.
func NewLicenseeLicense(
	licensee *Licensee,
	product Product,
	licenseStatus LicenseStatus,
	customerID uint64,
	expiresAt int64,
	suspendedAt *int64,
) *LicenseeLicense {
	return &LicenseeLicense{
		Key:           NewLicenseeLicenseKey(licensee.ID, licensee.Type, product, customerID),
		Licensee:      licensee,
		Product:       product,
		LicenseStatus: licenseStatus,
		CustomerID:    customerID,
		ExpiresAt:     expiresAt,
		SuspendedAt:   suspendedAt,
	}
}

// NewLicenseeLicenseForCustomerLicense creates a new LicenseeLicense for a given CustomerLicense.
func NewLicenseeLicenseForCustomerLicense(customerLicense *CustomerLicense) *LicenseeLicense {
	return NewLicenseeLicense(
		customerLicense.Licensee,
		customerLicense.Product,
		customerLicense.LicenseStatus,
		customerLicense.CustomerID,
		customerLicense.ExpiresAt,
		customerLicense.SuspendedAt,
	)
}

// NewLicenseeLicenseKey creates a new Key for a LicenseeLicense.
//
// pk format: {licenseeID}/licenseeLicense/{licenseeType}
//
// id format: {product}:{customerID}
func NewLicenseeLicenseKey(licenseeID string, licenseeType LicenseeType, product Product, customerID uint64) *Key {
	return &Key{
		PartitionKey: NewLicenseeLicensePartitionKey(licenseeID, licenseeType),
		ID:           NewLicenseeLicenseID(product, customerID),
	}
}

const pkLicenseeLicense = "LicenseeLicense"

// NewLicenseeLicensePartitionKey creates a new partition key for a LicenseeLicense.
//
// format: {licenseeID}/licenseeLicense/{licenseeType}
func NewLicenseeLicensePartitionKey(licenseeID string, licenseeType LicenseeType) string {
	return fmt.Sprintf("%s/%s/%s",
		licenseeID,
		pkLicenseeLicense,
		licenseeType,
	)
}

// NewLicenseeLicenseID creates an ID for a LicenseeLicense.
//
// format: {product}:{customerID}
func NewLicenseeLicenseID(product Product, customerID uint64) string {
	return fmt.Sprintf("%s:%d",
		product,
		customerID,
	)
}

// BuildCustomerLicenseKey creates a Key for a CustomerLicense from a LicenseeLicense.
func (ll *LicenseeLicense) BuildCustomerLicenseKey() *Key {
	return NewCustomerLicenseKey(
		ll.CustomerID,
		ll.Product,
		ll.Licensee.Type,
		ll.Licensee.ID,
	)
}

// BuildCustomerLicense creates a CustomerLicense from a LicenseeLicense.
func (ll *LicenseeLicense) BuildCustomerLicense() *CustomerLicense {
	return &CustomerLicense{
		Key:           ll.BuildCustomerLicenseKey(),
		CustomerID:    ll.CustomerID,
		Product:       ll.Product,
		Licensee:      ll.Licensee,
		ExpiresAt:     ll.ExpiresAt,
		LicenseStatus: ll.LicenseStatus,
		SuspendedAt:   ll.SuspendedAt,
	}
}

// GetLoggerFields returns a list of relevant fields for logging.
func (ll *LicenseeLicense) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.licensee_license.customer_id", ll.CustomerID),
		kvp.String("gh.licensee_license.product", ll.Product.String()),
		kvp.String("gh.licensee_license.status", ll.LicenseStatus.String()),
		kvp.String("gh.licensee_license.licensee.id", ll.Licensee.ID),
		kvp.String("gh.licensee_license.licensee.type", ll.Licensee.Type.String()),
		kvp.Time("gh.licensee_license.expires_at", time.Unix(ll.ExpiresAt, 0)),
		kvp.Int64p("gh.licensee_license.ttl", ll.TTL),
		kvp.Int64p("gh.licensee_license.suspended_at", ll.SuspendedAt),
	}
}

// Equal returns true if the fields of the two LicenseeLicense structs are equal.
func (ll *LicenseeLicense) Equal(other *LicenseeLicense) bool {
	if other == nil {
		return false
	}
	if ll == other {
		return true
	}

	suspendedAtEqual := ll.SuspendedAt == other.SuspendedAt ||
		(ll.SuspendedAt != nil && other.SuspendedAt != nil && *ll.SuspendedAt == *other.SuspendedAt)
	return ll.CustomerID == other.CustomerID &&
		ll.Product == other.Product &&
		ll.LicenseStatus == other.LicenseStatus &&
		ll.Licensee.ID == other.Licensee.ID &&
		ll.Licensee.Type == other.Licensee.Type &&
		ll.ExpiresAt == other.ExpiresAt &&
		suspendedAtEqual
}
