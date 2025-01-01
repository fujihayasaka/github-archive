// Package v1 contains the proto definitions for connecting to the internal turboghas endpoint in the monolith.
package v1

import (
	"database/sql/driver"
	"fmt"

	"github.com/pkg/errors"
)

func (e *UserType) Scan(val interface{}) (err error) {
	bytes, ok := val.([]byte)
	if !ok {
		return errors.Errorf("unknown user type format %T", val)
	}
	switch string(bytes) {
	case "Organization":
		*e = UserType_USER_TYPE_ORGANIZATION
	case "User":
		*e = UserType_USER_TYPE_USER
	default:
		*e = UserType_USER_TYPE_INVALID
		return errors.Errorf("unknown user type %q", val)
	}
	return nil
}

func (e UserType) Value() (driver.Value, error) {
	switch e {
	case UserType_USER_TYPE_ORGANIZATION:
		return "Organization", nil
	case UserType_USER_TYPE_USER:
		return "User", nil
	case UserType_USER_TYPE_INVALID:
		break
	}
	return "Invalid", errors.Errorf("invalid entity %q", e)
}

type EntityModel EntityType

func (e EntityModel) String() string {
	v, _ := EntityType(e).Value()
	s, _ := v.(string)
	return s
}

func (e *EntityType) Scan(val interface{}) (err error) {
	bytes, ok := val.([]byte)
	if !ok {
		return errors.Errorf("unknown entity type format %T", val)
	}
	switch string(bytes) {
	case "Business":
		*e = EntityType_ENTITY_TYPE_BUSINESS
	case "User":
		*e = EntityType_ENTITY_TYPE_USER
	default:
		*e = EntityType_ENTITY_TYPE_INVALID
		return errors.Errorf("unknown entity type %q", val)
	}
	return nil
}

func (e EntityType) ActorID(id uint64) string {
	switch e {
	case EntityType_ENTITY_TYPE_BUSINESS:
		return fmt.Sprintf("Business:%d", id)
	case EntityType_ENTITY_TYPE_USER:
		return fmt.Sprintf("User:%d", id)
	case EntityType_ENTITY_TYPE_INVALID:
		break
	}
	return fmt.Sprintf(":%d", id)
}

func (e EntityType) Value() (driver.Value, error) {
	switch e {
	case EntityType_ENTITY_TYPE_BUSINESS:
		return "Business", nil
	case EntityType_ENTITY_TYPE_USER:
		return "User", nil
	case EntityType_ENTITY_TYPE_INVALID:
		break
	}
	return "Invalid", errors.Errorf("invalid entity type %q", e)
}

func (s SKU) Value() (driver.Value, error) {
	if s == SKU_SKU_INVALID {
		return nil, fmt.Errorf("attempted to scan invalid value %v", s)
	}
	return int64(s), nil
}
