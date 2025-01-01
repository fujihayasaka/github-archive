package parsing

import (
	"fmt"
)

func missingRequiredAttrError(attrName string) error {
	return fmt.Errorf("missing required attribute %s", attrName)
}

func invalidAttributeTypeError(attrName string, expectedType string, actual interface{}) error {
	return fmt.Errorf("invalid attribute type for %s, expected %s but got %T", attrName, expectedType, actual)
}
