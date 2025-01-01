package models

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/github/licensify/internal/utils"
	"github.com/github/licensify/lib/globalid"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"golang.org/x/text/cases"
	"golang.org/x/text/language"
)

// Licensee represents a user/entity licensed for a product.
type Licensee struct {
	Type     LicenseeType
	ID       string
	GlobalID *globalid.GlobalID
}

// UnmarshalJSON unmarshals a Licensee from JSON.
// Note: ID can be a string or a number. We expect for IDs to be strings moving forward.
func (l *Licensee) UnmarshalJSON(data []byte) error {
	type Alias Licensee
	aux := &struct {
		ID interface{} `json:"ID"`
		*Alias
	}{
		Alias: (*Alias)(l),
	}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}

	switch v := aux.ID.(type) {
	case float64:
		l.ID = strconv.FormatUint(uint64(v), 10)
	case string:
		l.ID = v
	default:
		return fmt.Errorf("invalid type for ID: %T", v)
	}

	return nil
}

// NewLicensee creates a new Licensee.
func NewLicensee(t LicenseeType, id string) *Licensee {
	return &Licensee{
		Type: t,
		ID:   id,
		GlobalID: &globalid.GlobalID{
			App:       "git-hub",
			ModelName: cases.Title(language.Und, cases.NoLower).String(t.String()),
			ModelID:   id,
		},
	}
}

// NewLicenseeFromProto creates a new Licensee from a proto.Licensee.
func NewLicenseeFromProto(input *proto.Licensee) *Licensee {
	var id string
	switch {
	case input.Id != "":
		id = input.Id
	//nolint:staticcheck // Use IdDeprecated for backward compatibility
	case input.IdDeprecated != 0:
		id = strconv.FormatUint(input.IdDeprecated, 10)
	default:
		id = ""
	}

	globalID, _ := globalid.Parse(input.GlobalId)

	return &Licensee{
		Type:     LicenseeType(input.Type),
		ID:       id,
		GlobalID: globalID,
	}
}

// NewEnterpriseServerUserLicenseeWithEmail creates a new Licensee for a server user with an email address.
// The Licensee ID is a hash of the email address.
func NewEnterpriseServerUserLicenseeWithEmail(emailAddress string) (*Licensee, error) {
	licenseeID, err := utils.HashEmail(emailAddress)
	if err != nil {
		return nil, err
	}

	return &Licensee{
		Type: LicenseeTypeEnterpriseServerUser,
		ID:   licenseeID,
	}, nil
}

// NewEnterpriseServerUserLicenseeWithoutEmail creates a new Licensee for a server user without an email address.
// The Licensee ID is a hash of the enterprise installation user account's ID.
func NewEnterpriseServerUserLicenseeWithoutEmail(enterpriseInstallationUserAccountID uint64) (*Licensee, error) {
	licenseeID, err := utils.HashUint64(enterpriseInstallationUserAccountID)
	if err != nil {
		return nil, err
	}

	return &Licensee{
		Type: LicenseeTypeEnterpriseServerUser,
		ID:   licenseeID,
	}, nil
}

// NewLicenseeFromGlobalID create a new Licensee from a global id formatted string.
// It returns an error if the global is not parsable or is for an object that can't
// be a Licensee.
func NewLicenseeFromGlobalID(rawGlobalID string) (*Licensee, error) {
	globalID, err := globalid.Parse(rawGlobalID)
	if err != nil {
		return nil, err
	}

	licenseeType, ok := stringToLicensee[strings.ToLower(globalID.ModelName)]
	if !ok {
		return nil, fmt.Errorf("model name: %s is not valid for a Licensee", globalID.ModelName)
	}

	return &Licensee{
		Type:     licenseeType,
		ID:       globalID.ModelID,
		GlobalID: globalID,
	}, nil
}

// ToProto converts the Licensee to a proto.Licensee.
func (l *Licensee) ToProto() *proto.Licensee {
	uintID, err := strconv.ParseUint(l.ID, 10, 64)
	if err != nil {
		return nil
	}

	return &proto.Licensee{
		Type:         l.Type.ToProto(),
		IdDeprecated: uintID,
		GlobalId:     l.GlobalID.String(),
		Id:           l.ID,
	}
}

// LicenseeType represents the type of entity being licensed.
type LicenseeType byte

// LicenseeType constants.
const (
	LicenseeTypeUnspecified LicenseeType = iota
	LicenseeTypeUser
	LicenseeTypeEnterpriseServerUser
)

var (
	userToString = map[LicenseeType]string{
		LicenseeTypeUser:                 "user",
		LicenseeTypeEnterpriseServerUser: "enterprise-server-user",
	}
	stringToLicensee = map[string]LicenseeType{
		"user":                   LicenseeTypeUser,
		"enterprise-server-user": LicenseeTypeEnterpriseServerUser,
	}
)

// String returns the string representation of a LicenseeType.
func (l LicenseeType) String() string {
	return userToString[l]
}

// MarshalJSON marshals a LicenseeType to JSON.
func (l LicenseeType) MarshalJSON() ([]byte, error) {
	return json.Marshal(l.String())
}

// UnmarshalJSON unmarshals a LicenseeType from JSON.
func (l *LicenseeType) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	value, ok := stringToLicensee[s]
	if !ok {
		return fmt.Errorf("invalid Licensee: %s", s)
	}
	*l = value
	return nil
}

// ToProto converts a LicenseeType to a proto.LicenseeType.
func (l LicenseeType) ToProto() proto.LicenseeType {
	return proto.LicenseeType(l)
}
