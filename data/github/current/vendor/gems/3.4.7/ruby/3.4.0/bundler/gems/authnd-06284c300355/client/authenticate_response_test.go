package client

import (
	"strings"
	"testing"

	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/stretchr/testify/require"
)

func TestBuildsResponseFromEmptyStruct(t *testing.T) {
	twirpResponse := &pb.AuthenticateResponse{}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.NotNil(t, resp)
}

func TestResponseSucceededEmptyStruct(t *testing.T) {
	twirpResponse := &pb.AuthenticateResponse{}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.False(t, resp.Succeeded())
}

func TestResponseSucceededWhenResultFailed(t *testing.T) {
	for codeInt, codeName := range pb.AuthenticateResponse_Result_name {
		t.Run(codeName, func(t *testing.T) {
			code := pb.AuthenticateResponse_Result(codeInt)
			if code == pb.AuthenticateResponse_RESULT_SUCCESS {
				return
			}

			twirpResponse := &pb.AuthenticateResponse{
				Result: code,
			}
			resp, err := responseFromTwirp(twirpResponse)
			require.NoError(t, err)
			require.False(t, resp.Succeeded())
		})
	}
}

func TestResponseSucceededWhenResultSuccess(t *testing.T) {
	twirpResponse := &pb.AuthenticateResponse{
		Result: pb.AuthenticateResponse_RESULT_SUCCESS,
	}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.Equal(t, true, resp.Succeeded())
}

func TestResponseEmptyAttributes(t *testing.T) {
	twirpResponse := &pb.AuthenticateResponse{
		Result:     pb.AuthenticateResponse_RESULT_SUCCESS,
		Attributes: []*pb.Attribute{},
	}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.Equal(t, true, resp.Succeeded())
	require.Equal(t, 0, len(resp.Attributes))
}

func TestResponseAttributesNilValue(t *testing.T) {
	testAttributes := []*pb.Attribute{
		{
			Id:    "",
			Value: nil,
		},
	}
	twirpResponse := &pb.AuthenticateResponse{
		Result:     pb.AuthenticateResponse_RESULT_SUCCESS,
		Attributes: testAttributes,
	}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.Equal(t, true, resp.Succeeded())
	require.Equal(t, 1, len(resp.Attributes))
}

func TestResponseMultipleAttributes(t *testing.T) {
	testAttributes := []*pb.Attribute{
		{
			Id:    "test.attr",
			Value: nil,
		},
		{
			Id:    "test.attr.another",
			Value: nil,
		},
	}
	twirpResponse := &pb.AuthenticateResponse{
		Result:     pb.AuthenticateResponse_RESULT_SUCCESS,
		Attributes: testAttributes,
	}
	resp, err := responseFromTwirp(twirpResponse)
	require.NoError(t, err)
	require.Equal(t, true, resp.Succeeded())
	require.Equal(t, 2, len(resp.Attributes))
}

func TestGetStringAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetStringAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.int", "a.string", "string")
}

func TestGetIntAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetIntAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.bool", "a.int", int64(1))
}

func TestGetBoolAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetBoolAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.string", "a.bool", true)
}

func TestGetFloatAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetFloatAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.int", "a.float", 1.1)
}

func TestGetStringListAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetStringListAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.int", "a.string.list", []string{"string", "strings"})
}

func TestGetIntListAttribute(t *testing.T) {
	resp := responseWithAllAttributeTypes(t)
	wrappedGetter := func(a string) (interface{}, error) {
		return resp.GetIntegerListAttribute(a)
	}
	runTestForTypedAttributeFunc(t, wrappedGetter, "a.float", "a.int.list", []int64{1, 2})
}

func runTestForTypedAttributeFunc(t *testing.T, accessorFunc func(a string) (interface{}, error), wrongType string, rightType string, expectedRightTypeVal interface{}) {
	// test when the attribute key doesn't exist in the returned attributes
	_, err := accessorFunc("not.found")
	require.True(t, strings.Contains(err.Error(), errorAttributeNotFound.Error()))
	// test when the attribute key exists, but the value is nil
	_, err = accessorFunc("a.nil")
	require.True(t, strings.Contains(err.Error(), errorBadAttributeType.Error()))
	// test when the attribute key exists, but the value isn't the expected type
	_, err = accessorFunc(wrongType)
	require.True(t, strings.Contains(err.Error(), errorBadAttributeType.Error()))
	// test when the attribute key exists, and the value is the correct type
	val, err := accessorFunc(rightType)
	require.NoError(t, err)
	require.Equal(t, expectedRightTypeVal, val)
}

func responseWithAllAttributeTypes(t *testing.T) *AuthenticateResponse {
	testAttributes := []*pb.Attribute{
		{
			Id:    "a.nil",
			Value: nil,
		},
		{
			Id:    "a.string",
			Value: pb.NewStringValue("string"),
		},
		{
			Id:    "a.int",
			Value: pb.NewInt64Value(1),
		},
		{
			Id:    "a.float",
			Value: pb.NewDoubleValue(1.1),
		},
		{
			Id:    "a.bool",
			Value: pb.NewBoolValue(true),
		},
		{
			Id:    "a.string.list",
			Value: pb.NewStringListValue("string", "strings"),
		},
		{
			Id:    "a.int.list",
			Value: pb.NewIntegerListValue(1, 2),
		},
	}
	resp, err := responseFromTwirp(&pb.AuthenticateResponse{
		Result:     pb.AuthenticateResponse_RESULT_SUCCESS,
		Attributes: testAttributes,
	})
	require.NoError(t, err)
	return resp
}
