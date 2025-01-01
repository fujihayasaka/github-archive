package models

import (
	"fmt"
	"math"
	"slices"
	"strconv"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/kvp"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/google/uuid"
	"go.uber.org/zap/zapcore"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// MaxExpiresAt represents 9999-12-31T23:59:59Z in unix.
// This is the max time accepted by google.protobuf.Timestamp.
const MaxExpiresAt int64 = 253402300799

// CustomerLicense represents a customer license.
type CustomerLicense struct {
	*Key
	CosmosProperties
	CustomerID    uint64 `json:"CustomerId"`
	Product       Product
	LicenseStatus LicenseStatus
	Licensee      *Licensee
	Enablements   []*CustomerLicenseEnablement
	ExpiresAt     int64
	SuspendedAt   *int64
}

// NewCustomerLicense creates a new CustomerLicense struct.
func NewCustomerLicense(
	customerID uint64,
	product Product,
	licenseStatus LicenseStatus,
	licensee *Licensee,
	enablements []*CustomerLicenseEnablement,
	expiresAt int64,
	suspendedAt *int64,
) *CustomerLicense {
	return &CustomerLicense{
		Key:           NewCustomerLicenseKey(customerID, product, licensee.Type, licensee.ID),
		CustomerID:    customerID,
		Product:       product,
		LicenseStatus: licenseStatus,
		Licensee:      licensee,
		Enablements:   enablements,
		ExpiresAt:     expiresAt,
		SuspendedAt:   suspendedAt,
	}
}

// NewCustomerLicenseForUserWithOrgMemberships creates a new CustomerLicense for a user with the specified organization memberships.
func NewCustomerLicenseForUserWithOrgMemberships(customerID, userID uint64, orgIDs ...uint64) *CustomerLicense {
	return NewCustomerLicenseForUserWithMemberships(customerID, userID, orgIDs, nil)
}

// NewCustomerLicenseForUserWithMemberships creates a new CustomerLicense for a user with the specified org and repo memberships.
func NewCustomerLicenseForUserWithMemberships(customerID, userID uint64, orgIDs, repoIDs []uint64) *CustomerLicense {
	license := NewCustomerLicense(
		customerID,
		ProductSDLC,
		LicenseStatusActive,
		NewLicensee(LicenseeTypeUser, strconv.FormatUint(userID, 10)),
		[]*CustomerLicenseEnablement{},
		MaxExpiresAt,
		nil,
	)

	license.AddOrgMemberships(orgIDs...)
	license.AddRepositoryCollaborators(repoIDs...)
	return license
}

// NewCustomerLicenseForUserWithRepositoryCollaborator creates a new CustomerLicense for a user with the specified repository collaborators.
func NewCustomerLicenseForUserWithRepositoryCollaborator(customerID, userID, repoID uint64) *CustomerLicense {
	license := NewCustomerLicense(
		customerID,
		ProductSDLC,
		LicenseStatusActive,
		NewLicensee(LicenseeTypeUser, strconv.FormatUint(userID, 10)),
		[]*CustomerLicenseEnablement{},
		MaxExpiresAt,
		nil,
	)
	license.AddRepositoryCollaborators(repoID)
	return license
}

// NewCustomerLicenseForEnterpriseServerUserWithEmail creates a new CustomerLicense for a server installation user by email
func NewCustomerLicenseForEnterpriseServerUserWithEmail(customerID uint64, email string) (*CustomerLicense, error) {
	licensee, err := NewEnterpriseServerUserLicenseeWithEmail(email)
	if err != nil {
		return nil, err
	}

	license := NewCustomerLicense(
		customerID,
		ProductSDLC,
		LicenseStatusActive,
		licensee,
		[]*CustomerLicenseEnablement{},
		MaxExpiresAt,
		nil,
	)
	return license, nil
}

// NewCustomerLicenseForEnterpriseServerUserWithoutEmail creates a new CustomerLicense for a server installation user by enterprise installation user account ID
func NewCustomerLicenseForEnterpriseServerUserWithoutEmail(customerID, enterpriseInstallationUserAccountID uint64) (*CustomerLicense, error) {
	licensee, err := NewEnterpriseServerUserLicenseeWithoutEmail(enterpriseInstallationUserAccountID)
	if err != nil {
		return nil, err
	}

	license := NewCustomerLicense(
		customerID,
		ProductSDLC,
		LicenseStatusActive,
		licensee,
		[]*CustomerLicenseEnablement{},
		MaxExpiresAt,
		nil,
	)
	return license, nil
}

// NewCustomerLicenseFromProto creates a new CustomerLicense from a proto.CustomerLicense.
func NewCustomerLicenseFromProto(input *proto.CustomerLicense) *CustomerLicense {
	enablements := make([]*CustomerLicenseEnablement, len(input.Enablements))
	for i, e := range input.Enablements {
		enablements[i] = NewCustomerLicenseEnablementFromProto(e)
	}

	var suspendedAt *int64
	if input.SuspendedAt != nil {
		timestamp := input.SuspendedAt.AsTime().Unix()
		suspendedAt = &timestamp
	}

	return NewCustomerLicense(
		input.CustomerId,
		Product(input.Product),
		LicenseStatus(input.LicenseStatus),
		NewLicenseeFromProto(input.Licensee),
		enablements,
		input.ExpiresAt.AsTime().Unix(),
		suspendedAt,
	)
}

// ToProto converts the CustomerLicense to a proto.CustomerLicense.
func (cl *CustomerLicense) ToProto() *proto.CustomerLicense {
	enablementsProtos := make([]*proto.CustomerLicenseEnablement, len(cl.Enablements))
	for i, e := range cl.Enablements {
		enablementsProtos[i] = e.ToProto()
	}

	var suspendedAt *timestamppb.Timestamp
	if cl.SuspendedAt != nil {
		suspendedAt = timestamppb.New(time.Unix(*cl.SuspendedAt, 0))
	}

	return &proto.CustomerLicense{
		CustomerId:    cl.CustomerID,
		Product:       cl.Product.ToProto(),
		LicenseStatus: cl.LicenseStatus.ToProto(),
		Licensee:      cl.Licensee.ToProto(),
		Enablements:   enablementsProtos,
		ExpiresAt:     timestamppb.New(time.Unix(cl.ExpiresAt, 0)),
		SuspendedAt:   suspendedAt,
	}
}

// AddETag generates a new ETag and sets it on the CustomerLicense.
//
// Useful when multiple licenses being newly created in a short timeframe. When
// their PKs match this may overwrite each other without a unique ETag.
func (cl *CustomerLicense) AddETag() {
	eTag := azcore.ETag(uuid.New().String())
	cl.ETag = &eTag
}

// GetEnablementFor returns the first enablement that matches the provided type and reason.
func (cl *CustomerLicense) GetEnablementFor(t ProductEnablementType, er EnablementReason) *CustomerLicenseEnablement {
	for _, e := range cl.Enablements {
		if e.Type == t && e.Reason == er {
			return e
		}
	}
	return nil
}

// AddEnablementFor adds an ID to the enablement that matches the provided type and reason.
// It returns true if an enablement was modified.
func (cl *CustomerLicense) AddEnablementFor(t ProductEnablementType, er EnablementReason, ids ...uint64) bool {
	if ids == nil {
		return false
	}
	enablement := cl.GetEnablementFor(t, er)
	if enablement == nil {
		enablement = NewCustomerLicenseEnablement(t, er, nil)
		cl.Enablements = append(cl.Enablements, enablement)
	}
	return enablement.AddIDs(ids...)
}

// RemoveEnablementFor removes an ID from the enablement that matches the provided type and reason.
// If the enablement is empty after removing the ID, it will be removed from the license.
// It returns true if an enablement was modified/removed.
func (cl *CustomerLicense) RemoveEnablementFor(t ProductEnablementType, er EnablementReason, ids ...uint64) bool {
	enablement := cl.GetEnablementFor(t, er)
	if enablement == nil {
		return false
	}
	modified := enablement.RemoveIDs(ids...)
	if enablement.IsEmpty() {
		modified = cl.RemoveEnablement(t, er)
	}
	return modified
}

// RemoveEnablement removes all enablements that matches the provided type and reason.
// It returns true if the license was modified.
func (cl *CustomerLicense) RemoveEnablement(t ProductEnablementType, er EnablementReason) bool {
	prevLen := len(cl.Enablements)
	cl.Enablements = slices.DeleteFunc(cl.Enablements, func(e *CustomerLicenseEnablement) bool {
		return e.Type == t && e.Reason == er
	})
	return prevLen != len(cl.Enablements)
}

// AddOrgMemberships adds an organization to the org membership enablement.
// It returns true if the license was modified.
func (cl *CustomerLicense) AddOrgMemberships(orgIDs ...uint64) bool {
	return cl.AddEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, orgIDs...)
}

// RemoveOrgMemberships removes an organization from the org membership enablement.
// It returns true if the license was modified.
func (cl *CustomerLicense) RemoveOrgMemberships(orgIDs ...uint64) bool {
	return cl.RemoveEnablementFor(ProductEnablementTypeOrg, EnablementReasonOrgMembership, orgIDs...)
}

// AddRepositoryCollaborators adds an outside collaborator to a repository within the organization.
// It returns true if the license was modified.
func (cl *CustomerLicense) AddRepositoryCollaborators(repoIDs ...uint64) bool {
	return cl.AddEnablementFor(ProductEnablementTypeRepo, EnablementReasonRepositoryCollaborator, repoIDs...)
}

// RemoveRepositoryCollaborator removes an outside collaborator from a repository within the organization.
// It returns true if the license was modified.
func (cl *CustomerLicense) RemoveRepositoryCollaborator(repoIDs ...uint64) bool {
	return cl.RemoveEnablementFor(ProductEnablementTypeRepo, EnablementReasonRepositoryCollaborator, repoIDs...)
}

// ReplaceOrgMemberships replaces all org memberships with the provided org IDs.
// Any org memberships not in the provided list will be removed.
// It returns true if the license was modified.
func (cl *CustomerLicense) ReplaceOrgMemberships(orgIDs ...uint64) bool {
	return cl.ReplaceEnablementIDs(ProductEnablementTypeOrg, EnablementReasonOrgMembership, orgIDs...)
}

// ReplaceRepositoryCollaborators replaces all repository collaborators with the provided org IDs.
// Any repository collaborators not in the provided list will be removed.
// It returns true if the license was modified.
func (cl *CustomerLicense) ReplaceRepositoryCollaborators(repoIDs ...uint64) bool {
	return cl.ReplaceEnablementIDs(ProductEnablementTypeRepo, EnablementReasonRepositoryCollaborator, repoIDs...)
}

// ReplaceEnablementIDs replaces all enablement IDs for the provided type and reason.
// Any IDs not in the provided list will be removed.
// It returns true if the license was modified.
func (cl *CustomerLicense) ReplaceEnablementIDs(t ProductEnablementType, er EnablementReason, ids ...uint64) bool {
	var modified bool
	enablement := cl.GetEnablementFor(t, er)
	existingIDs := make(map[uint64]struct{})
	if enablement != nil {
		if enablement.IsEmpty() && ids == nil {
			// Remove the enablement if the list is empty and no IDs are provided.
			// This is to clean up any empty enablements that may exist.
			return cl.RemoveEnablement(t, er)
		}
		for _, id := range enablement.EnablementIDs {
			existingIDs[id] = struct{}{}
		}
	}
	for _, id := range ids {
		if cl.AddEnablementFor(t, er, id) {
			modified = true
		}
		delete(existingIDs, id)
	}
	for id := range existingIDs {
		if cl.RemoveEnablementFor(t, er, id) {
			modified = true
		}
	}
	return modified
}

// IsEmpty returns true if the CustomerLicense has no enablements.
func (cl *CustomerLicense) IsEmpty() bool {
	return len(cl.Enablements) == 0
}

// SetStatus sets the license status
// It returns true if the status was modified.
func (cl *CustomerLicense) SetStatus(licenseStatus LicenseStatus) bool {
	if cl.LicenseStatus == licenseStatus {
		return false
	}
	cl.LicenseStatus = licenseStatus
	return true
}

// SetExpiresAt sets the expires at time.
// It returns true if the expires at time was modified.
func (cl *CustomerLicense) SetExpiresAt(expiresAt int64) bool {
	if cl.ExpiresAt == expiresAt {
		return false
	}
	cl.ExpiresAt = expiresAt
	return true
}

// Activate sets the license status to active, sets the expires at time to the max time and sets the suspended at time to nil.
// It returns true if any of the fields were modified
func (cl *CustomerLicense) Activate() bool {
	statusModified := cl.SetStatus(LicenseStatusActive)
	expiresModified := cl.SetExpiresAt(MaxExpiresAt)
	suspendedModified := cl.SetSuspendedAt(nil)
	return statusModified || expiresModified || suspendedModified
}

// Deactivate sets the license status to deactivated and sets the expires at time to the end of the month.
// It returns true if the status or expires at time was modified.
func (cl *CustomerLicense) Deactivate() bool {
	statusModified := cl.SetStatus(LicenseStatusDeactivated)
	expiresModified := cl.SetExpiresAt(EndOfMonth())
	return statusModified || expiresModified
}

// Suspend sets the license status to suspended and sets the suspended at time.
// It returns true if the status or suspended at time was modified.
func (cl *CustomerLicense) Suspend(suspendedAt int64) bool {
	statusModified := cl.SetStatus(LicenseStatusSuspended)
	suspendedModified := cl.SetSuspendedAt(&suspendedAt)
	return statusModified || suspendedModified
}

// SetSuspendedAt sets the suspended at time.
// It returns true if the SuspendedAt value was modified.
func (cl *CustomerLicense) SetSuspendedAt(suspendedAt *int64) bool {
	if cl.SuspendedAt == suspendedAt {
		return false
	}
	if cl.SuspendedAt != nil && suspendedAt != nil && *cl.SuspendedAt == *suspendedAt {
		return false
	}
	cl.SuspendedAt = suspendedAt
	return true
}

// GetLicenseeLicenseKey returns a Key for the LicenseeLicense.
func (cl *CustomerLicense) GetLicenseeLicenseKey() *Key {
	return NewLicenseeLicenseKey(cl.Licensee.ID, cl.Licensee.Type, cl.Product, cl.CustomerID)
}

// GetLoggerFields returns a list of relevant fields for logging.
func (cl *CustomerLicense) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.customer_license.customer_id", cl.CustomerID),
		kvp.String("gh.customer_license.product", cl.Product.String()),
		kvp.String("gh.customer_license.status", cl.LicenseStatus.String()),
		kvp.String("gh.customer_license.licensee.id", cl.Licensee.ID),
		kvp.String("gh.customer_license.licensee.type", cl.Licensee.Type.String()),
		kvp.String("gh.customer_license.enablements", fmt.Sprintf("%s", cl.Enablements)),
		kvp.Time("gh.customer_license.expires_at", time.Unix(cl.ExpiresAt, 0)),
		kvp.Int64p("gh.customer_license.ttl", cl.TTL),
		kvp.Int64p("gh.customer_license.suspended_at", cl.SuspendedAt),
	}
}

// NewCustomerLicenseKeyFromProto creates a new Key for a CustomerLicense from a proto.
//
//nolint:staticcheck // Use IdDeprecated for backward compatibility
func NewCustomerLicenseKeyFromProto(input *proto.CustomerLicense) *Key {
	var licenseeID string
	switch {
	case input.Licensee.Id != "":
		licenseeID = input.Licensee.Id
	case input.Licensee.IdDeprecated != 0:
		licenseeID = strconv.FormatUint(input.Licensee.IdDeprecated, 10)
	default:
		licenseeID = ""
	}

	return NewCustomerLicenseKey(
		input.CustomerId,
		Product(input.Product),
		LicenseeType(input.Licensee.Type),
		licenseeID,
	)
}

// NewCustomerLicenseKey creates a new Key for a CustomerLicense.
//
// pk format: {customerID}/customerLicense/{product}
//
// id format: {licenseeType}:{licenseeID}.
func NewCustomerLicenseKey(customerID uint64, product Product, licenseeType LicenseeType, licenseeID string) *Key {
	return &Key{
		PartitionKey: NewCustomerLicensePartitionKey(customerID, product),
		ID:           NewCustomerLicenseID(licenseeType, licenseeID),
	}
}

const pkCustomerLicense = "CustomerLicense"

// NewCustomerLicensePartitionKey creates a partition key for a CustomerLicense.
//
// format: {customerID}/customerLicense/{product}
func NewCustomerLicensePartitionKey(customerID uint64, product Product) string {
	return fmt.Sprintf("%d/%s/%s",
		customerID,
		pkCustomerLicense,
		product,
	)
}

// NewCustomerLicenseID creates ID for a CustomerLicense.
//
// format: {licenseeType}:{licenseeID}
func NewCustomerLicenseID(licenseeType LicenseeType, licenseeID string) string {
	return fmt.Sprintf("%s:%s",
		licenseeType,
		licenseeID,
	)
}

// LicenseeIDToInt64 converts the licensee ID string to a int64.
func (cl *CustomerLicense) LicenseeIDToInt64() int64 {
	idAsInt64, err := strconv.ParseInt(cl.Licensee.ID, 10, 64)
	if err != nil {
		fmt.Println("error converting licensee ID to int64")
		return 0
	}
	return idAsInt64
}

// CustomerIDToInt64 converts the customer ID to a int64.
func (cl *CustomerLicense) CustomerIDToInt64() int64 {
	if cl.CustomerID > uint64(math.MaxInt64) {
		fmt.Println("CustomerID is out of int64 range")
		return 0
	}
	//nolint:gosec // CustomerID is guaranteed to be within the int64 range.
	return int64(cl.CustomerID)
}
