package models

import (
	"reflect"
	"sort"

	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"

	pb "github.com/github/authnd/client/proto/authentication/v0"
)

func MapPayloadToAttributes(parentAttributeId string, payload map[string]interface{}) ([]*pb.Attribute, error) {
	childAttrs := make([]*pb.Attribute, 0, len(payload))

	v := reflect.ValueOf(payload)
	for v.Kind() == reflect.Ptr {
		v = v.Elem()
	}

	iter := v.MapRange()
	for iter.Next() {
		childID := parentAttributeId + ":" + iter.Key().String()
		childPtr := iter.Value()
		// If the value is 'nil', just skip it.
		if !childPtr.IsZero() {
			child := childPtr.Elem()
			attr, err := attributeForPrimitive(childID, child)
			if err != nil {
				return nil, err
			}
			childAttrs = append(childAttrs, attr)
		}
	}

	// map traversal is nondeterministic in Go, by design.  sort the list of attributes here
	// to ensure the protobuf response is stable (i.e. attributes are returned in the same order
	// for the same request every time).
	sort.Slice(childAttrs, func(i, j int) bool {
		if childAttrs[i] == nil {
			return false
		}
		if childAttrs[j] == nil {
			return true
		}
		return childAttrs[i].Id < childAttrs[j].Id
	})

	return childAttrs, nil
}

func SerializeAttributes(attrs []*pb.Attribute) ([]byte, error) {
	list := &pb.AttributeList{Attributes: attrs}
	return proto.Marshal(list)
}

func DeserializeAttributes(attrs []byte) ([]*pb.Attribute, error) {
	var list pb.AttributeList
	err := proto.Unmarshal(attrs, &list)
	if err != nil {
		return nil, err
	}
	return list.Attributes, nil
}

func GetAttributeById(attrs []*pb.Attribute, id string) *pb.Attribute {
	if attrs == nil {
		return nil
	}

	for _, attr := range attrs {
		if attr.Id == id {
			return attr
		}
	}
	return nil
}

func GetAttributeValue(attrs []*pb.Attribute, id string) (*pb.Value, bool) {
	attr := GetAttributeById(attrs, id)
	if attr == nil {
		return nil, false
	}

	return attr.Value, true
}

func attributeForPrimitive(id string, value reflect.Value) (*pb.Attribute, error) {
	switch kind := value.Type().Kind(); kind {
	case reflect.Bool:
		return pb.NewBoolAttribute(id, value.Bool()), nil
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return pb.NewInt64Attribute(id, int64(value.Int())), nil
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return pb.NewInt64Attribute(id, int64(value.Uint())), nil
	case reflect.Float32, reflect.Float64:
		return pb.NewDoubleAttribute(id, float64(value.Float())), nil
	case reflect.String:
		return pb.NewStringAttribute(id, value.String()), nil
	default:
		return nil, errors.Errorf("unsupported kind for expected primitive-typed field %s: %+v", id, kind)
	}
}
