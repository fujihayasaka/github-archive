package types

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/pkg/errors"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
)

type Owner struct {
	login string
}

// Creates an owner that isn't tenant aware (it may or may not have a tenant shortcode suffix)
func NewOwner(login string) (Owner, error) {
	if !IsValidLogin(login) {
		return Owner{}, errors.Errorf("%q is not a valid login", login)
	}

	return Owner{login}, nil
}

// https://github.com/github/github/blob/019eb317ad8bc2c061edc2c82caf241447c16079/packages/users/app/models/user.rb#L52
// This is a combo of valid dotcom user logins and valid EMU logins (with tenant suffix) so that we can support proxima.
var loginRegex = regexp.MustCompile(`\A[a-zA-Z0-9]+[a-zA-Z0-9_-]*\z`)

// IsValidLogin returns true if the login string matches the rules for valid
// logins on github.com.
func IsValidLogin(login string) bool {
	return loginRegex.MatchString(login)
}

// Takes an owner login (that may or may not have a tenant shortcode suffix) and an optional tenant
// and returns a unique login.
func (o Owner) UniqueLogin(tenant *pb.Tenant) string {
	if tenant == nil {
		return o.login
	}
	login := strings.TrimSuffix(o.login, fmt.Sprintf("_%s", tenant.Shortcode))
	return fmt.Sprintf("%s_%s", login, tenant.Shortcode)
}

// Takes an owner login (that may or may not have a tenant shortcode suffix) and an optional tenant
// and returns a display login.
func (o Owner) DisplayLogin(tenant *pb.Tenant) string {
	if tenant == nil {
		return o.login
	}
	return strings.TrimSuffix(o.login, fmt.Sprintf("_%s", tenant.Shortcode))
}

// Returns the unique login string (includes tenant shortcode suffix if there is one)
func (o Owner) String() string {
	return o.login
}

func (o Owner) Equal(other Owner) bool {
	return strings.EqualFold(o.String(), other.String())
}
