package models

import (
	"fmt"
	"testing"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/authnd/internal/api/testhelpers"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
)

func TestMapPayloadToAttributes(t *testing.T) {
	tests := map[string]struct {
		parentAttributeId string
		payload           map[string]interface{}
		want              []*pb.Attribute
		err               string
	}{
		"valid": {
			parentAttributeId: client.CredentialPayloadAttribute,
			payload: map[string]interface{}{
				"foo":        "bar",
				"foobool":    true,
				"fooint":     int64(3),
				"fooint32":   int32(32),
				"foouint16":  uint16(16),
				"foofloat32": float32(32.0),
				"foofloat64": float64(64.0),
			},
			want: []*pb.Attribute{
				pb.NewStringAttribute(fmt.Sprintf("%s:foo", client.CredentialPayloadAttribute), "bar"),
				pb.NewBoolAttribute(fmt.Sprintf("%s:foobool", client.CredentialPayloadAttribute), true),
				pb.NewDoubleAttribute(fmt.Sprintf("%s:foofloat32", client.CredentialPayloadAttribute), 32.0),
				pb.NewDoubleAttribute(fmt.Sprintf("%s:foofloat64", client.CredentialPayloadAttribute), 64.0),
				pb.NewInt64Attribute(fmt.Sprintf("%s:fooint", client.CredentialPayloadAttribute), 3),
				pb.NewInt64Attribute(fmt.Sprintf("%s:fooint32", client.CredentialPayloadAttribute), 32),
				pb.NewInt64Attribute(fmt.Sprintf("%s:foouint16", client.CredentialPayloadAttribute), 16),
			},
		},
		"nil value in payload": {
			parentAttributeId: client.CredentialPayloadAttribute,
			payload: map[string]interface{}{
				"foo": nil,
			},
			want: []*pb.Attribute{},
		},
		"zero/falsey values in payload": {
			parentAttributeId: client.CredentialPayloadAttribute,
			payload: map[string]interface{}{
				"fooint":  0,
				"foobool": false,
			},
			want: []*pb.Attribute{
				pb.NewInt64Attribute(fmt.Sprintf("%s:fooint", client.CredentialPayloadAttribute), 0),
				pb.NewBoolAttribute(fmt.Sprintf("%s:foobool", client.CredentialPayloadAttribute), false),
			},
		},
	}

	for name, tc := range tests {
		t.Run(name, func(t *testing.T) {
			got, err := MapPayloadToAttributes(tc.parentAttributeId, tc.payload)

			// proto.Equal is not able to compare slices so we wrap them with a
			// comparable type
			g := &pb.AuthenticateResponse{Attributes: got}
			w := &pb.AuthenticateResponse{Attributes: tc.want}

			if err != nil {
				require.Equal(t, tc.err, err.Error())
			} else if equal := proto.Equal(w, g); !equal {
				testhelpers.RequireEqualAttributeSlices(t, tc.want, got, true)
			}
		})
	}
}
