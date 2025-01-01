package models

import (
	"encoding/json"
	"fmt"
	"slices"

	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
)

// EnablementReason represents the reason a licensee is consuming a license for the product,
// ex: organization membership for GHE.
type EnablementReason int32

// EnablementReason constants.
const (
	EnablementReasonUnspecified EnablementReason = iota
	EnablementReasonOrgMembership
	EnablementReasonRepositoryCollaborator
	EnablementReasonEnterpriseServerUser
)

var (
	enablementReasonToString = map[EnablementReason]string{
		EnablementReasonOrgMembership:          "organizationMembership",
		EnablementReasonRepositoryCollaborator: "repositoryCollaborator",
		EnablementReasonEnterpriseServerUser:   "enterpriseServerUser",
	}
	stringToEnablementReason = map[string]EnablementReason{
		"organizationMembership": EnablementReasonOrgMembership,
		"repositoryCollaborator": EnablementReasonRepositoryCollaborator,
		"enterpriseServerUser":   EnablementReasonEnterpriseServerUser,
	}
)

// String returns the string representation of a EnablementReason.
func (er EnablementReason) String() string {
	return enablementReasonToString[er]
}

// MarshalJSON marshals a EnablementReason to JSON.
func (er *EnablementReason) MarshalJSON() ([]byte, error) {
	return json.Marshal(er.String())
}

// UnmarshalJSON unmarshals a EnablementReason from JSON.
func (er *EnablementReason) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	value, ok := stringToEnablementReason[s]
	if !ok {
		return fmt.Errorf("invalid EnablementReason: %s", s)
	}
	*er = value
	return nil
}

// ToProto converts a EnablementReason to a proto.EnablementReason.
func (er *EnablementReason) ToProto() proto.EnablementReason {
	return proto.EnablementReason(*er)
}

// CustomerLicenseEnablement represents an enablement that a customer has for a product.
type CustomerLicenseEnablement struct {
	Type          ProductEnablementType
	Reason        EnablementReason
	EnablementIDs []uint64
}

// AddIDs adds an ID to the EnablementIDs if it's not already in the list
// and returns true if the list was modified.
func (c *CustomerLicenseEnablement) AddIDs(ids ...uint64) bool {
	prevLen := len(c.EnablementIDs)
	for _, id := range ids {
		if !slices.Contains(c.EnablementIDs, id) {
			c.EnablementIDs = append(c.EnablementIDs, id)
		}
	}
	return len(c.EnablementIDs) != prevLen
}

// RemoveIDs removes all elements matching the provided ID
// and returns true if the list was modified.
func (c *CustomerLicenseEnablement) RemoveIDs(ids ...uint64) bool {
	prevLen := len(c.EnablementIDs)
	c.EnablementIDs = slices.DeleteFunc(c.EnablementIDs, func(i uint64) bool {
		return slices.Contains(ids, i)
	})
	return len(c.EnablementIDs) != prevLen
}

// IsEmpty returns true if the CustomerLicenseEnablement ids list is empty.
func (c *CustomerLicenseEnablement) IsEmpty() bool {
	return len(c.EnablementIDs) == 0
}

// NewCustomerLicenseEnablement creates a new CustomerLicenseEnablement struct.
func NewCustomerLicenseEnablement(t ProductEnablementType, er EnablementReason, ids []uint64) *CustomerLicenseEnablement {
	return &CustomerLicenseEnablement{
		Type:          t,
		Reason:        er,
		EnablementIDs: ids,
	}
}

// NewCustomerLicenseEnablementFromProto creates a new CustomerLicenseEnablement from a proto.CustomerLicenseEnablement.
func NewCustomerLicenseEnablementFromProto(input *proto.CustomerLicenseEnablement) *CustomerLicenseEnablement {
	return NewCustomerLicenseEnablement(
		ProductEnablementType(input.Type),
		EnablementReason(input.Reason),
		input.EnablementIds,
	)
}

// ToProto converts a CustomerLicenseEnablement to a proto.CustomerLicenseEnablement.
func (c *CustomerLicenseEnablement) ToProto() *proto.CustomerLicenseEnablement {
	return &proto.CustomerLicenseEnablement{
		Type:          proto.ProductEnablementType(c.Type),
		Reason:        proto.EnablementReason(c.Reason),
		EnablementIds: c.EnablementIDs,
	}
}

// String returns the enablement fields as a string for logging/debugging.
func (c *CustomerLicenseEnablement) String() string {
	return fmt.Sprintf("Type=%s Reason=%s EnablementIDs=%d", c.Type, c.Reason, c.EnablementIDs)
}
