package v0

import (
	"time"

	"github.com/pkg/errors"
	timestamppb "google.golang.org/protobuf/types/known/timestamppb"
)

// Known token type values
const (
	ProgrammaticAccessTokenType string = "ProgrammaticAccessToken"
)

// attribute helpers copied from
// https://github.com/github/authzd/blob/5135466e300f93338f15a3fe4a2124d887208fad/pkg/proto/helpers.go

// NewNullAttribute creates an Attribute containing a NullValue.
func NewNullAttribute(id string) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewNullValue(),
	}
}

// NewNullValue creates a Value structure containing a NullValue
func NewNullValue() *Value {
	return &Value{
		Kind: &Value_NullValue{},
	}
}

// NewBoolAttribute creates an Attribute containing a BoolValue.
func NewBoolAttribute(id string, b bool) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewBoolValue(b),
	}
}

// NewBoolValue creates a Value structure from the given bool
func NewBoolValue(b bool) *Value {
	return &Value{
		Kind: &Value_BoolValue{
			BoolValue: b,
		},
	}
}

// NewInt64Attribute creates an Attribute containing an Int64Value.
func NewInt64Attribute(id string, i int64) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewInt64Value(i),
	}
}

// NewInt64Value creates a Value structure from the given int64
func NewInt64Value(i int64) *Value {
	return &Value{
		Kind: &Value_IntegerValue{
			IntegerValue: i,
		},
	}
}

// NewDoubleAttribute creates an Attribute containing a DoubleValue.
func NewDoubleAttribute(id string, d float64) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewDoubleValue(d),
	}
}

// NewDoubleValue creates a Value structure from the given double
func NewDoubleValue(d float64) *Value {
	return &Value{
		Kind: &Value_DoubleValue{
			DoubleValue: d,
		},
	}
}

// NewStringAttribute creates an Attribute containing a StringValue.
func NewStringAttribute(id, s string) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewStringValue(s),
	}
}

// NewStringValue creates a Value structure from the given string
func NewStringValue(s string) *Value {
	return &Value{
		Kind: &Value_StringValue{
			StringValue: s,
		},
	}
}

// NewStringAttribute creates an Attribute containing a StringValue.
func NewTimeAttribute(id string, t time.Time) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewTimeValue(t),
	}
}

// NewStringValue creates a Value structure from the given string
func NewTimeValue(t time.Time) *Value {
	return &Value{
		Kind: &Value_TimeValue{
			TimeValue: timestamppb.New(t),
		},
	}
}

// NewStringLiteAttribute creates an Attribute containing a list of strings.
func NewStringListAttribute(id string, values ...string) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewStringListValue(values...),
	}
}

// NewStringListValue creates a Value structure from the given list of strings
func NewStringListValue(values ...string) *Value {
	return &Value{
		Kind: &Value_StringListValue{
			StringListValue: &StringList{Values: values},
		},
	}
}

// NewIntegerListAttribute creates an Attribute containiner a list of int64s.
func NewIntegerListAttribute(id string, values ...int64) *Attribute {
	return &Attribute{
		Id:    id,
		Value: NewIntegerListValue(values...),
	}
}

// NewIntegerListValue creates a Value structure from the given list of strings
func NewIntegerListValue(values ...int64) *Value {
	return &Value{
		Kind: &Value_IntegerListValue{
			IntegerListValue: &IntegerList{Values: values},
		},
	}
}

// NewSSHPublicKeyCredential creates a Credentials structure for the provided SSH public key
func NewSSHPublicKeyCredential(key string) *Credentials {
	return &Credentials{
		Kind: &Credentials_SshPublicKey{
			SshPublicKey: &SSHPublicKey{
				Key: key,
			},
		},
	}
}

// NewLoginPasswordCredential creates a Credentials structure for the provided login and password
func NewLoginPasswordCredential(login, password string) *Credentials {
	return &Credentials{
		Kind: &Credentials_LoginPassword{
			LoginPassword: &LoginPassword{
				Login:    login,
				Password: password,
			},
		},
	}
}

// NewAccessTokenCredential creates a Credentials structure for the provided access token
func NewAccessTokenCredential(token string) *Credentials {
	return &Credentials{
		Kind: &Credentials_AccessToken{
			AccessToken: &AccessToken{
				Token: token,
			},
		},
	}
}

func NewSignedAuthTokenCredential(token, scope string) *Credentials {
	return &Credentials{
		Kind: &Credentials_SignedAuthToken{
			SignedAuthToken: &SignedAuthToken{
				Token: token,
				Scope: scope,
			},
		},
	}
}

func (m *Value) Unwrap() (interface{}, error) {
	switch t := m.GetKind().(type) {
	case *Value_NullValue, nil:
		return nil, nil
	case *Value_BoolValue:
		return t.BoolValue, nil
	case *Value_IntegerValue:
		return t.IntegerValue, nil
	case *Value_DoubleValue:
		return t.DoubleValue, nil
	case *Value_StringValue:
		return t.StringValue, nil
	case *Value_TimeValue:
		return t.TimeValue.AsTime(), nil
	case *Value_IntegerListValue:
		return t.IntegerListValue.Values, nil
	case *Value_StringListValue:
		return t.StringListValue.Values, nil
	default:
		return nil, errors.Errorf("%T is an unknown protocol buffers type", t)
	}
}

const (
	NullKind        = "null"
	BoolKind        = "bool"
	IntegerKind     = "integer"
	DoubleKind      = "double"
	StringKind      = "string"
	StringListKind  = "string_list"
	IntegerListKind = "integer_list"
)

func (m *Value) GetKindName() string {
	switch m.GetKind().(type) {
	case *Value_NullValue, nil:
		return NullKind
	case *Value_BoolValue:
		return BoolKind
	case *Value_IntegerValue:
		return IntegerKind
	case *Value_DoubleValue:
		return DoubleKind
	case *Value_StringValue:
		return StringKind
	case *Value_IntegerListValue:
		return IntegerListKind
	case *Value_StringListValue:
		return StringListKind
	default:
		return ""
	}
}

// CredentialTypeName returns a human readable string of the given credentials type.
func CredentialTypeName(creds *Credentials) string {
	switch creds.GetKind().(type) {
	case *Credentials_LoginPassword:
		return "login_password"
	case *Credentials_SshPublicKey:
		return "ssh_public_key"
	case *Credentials_AccessToken:
		return "access_token"
	case *Credentials_SignedAuthToken:
		return "signed_auth_token"
	default:
		return "unknown"
	}
}
