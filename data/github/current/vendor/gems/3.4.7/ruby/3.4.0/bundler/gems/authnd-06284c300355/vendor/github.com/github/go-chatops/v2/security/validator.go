package security

import (
	"errors"
	"fmt"
	"strings"
)

/*

## Summary

Validator can perform several different types of security validations on a
chatops request and enforce user-defined authorization policies.

It currently handles:
* Restricting commands to valid rooms
* Restricting commands to valid user groups (Role Based Access Control)
* Enforcing two factor auth before commands

## RBAC

The RBAC needs to pull user group membership information from another source.
Currently this is defined as any object which can satisfy the UserGroupsGetter interface.

This interface has one method:
`GetGroupsOfUser(username string) ([]string, error)`

A few utility functions exist which can be used to create an LDAPClient object which
provides this method since LDAP is a common source of authority for user and role
access information.

## Two Factor Auth

Similarly two factor auth needs to be satisfied by an external dependency.  This
is defined by the TwoFactorAuthorizer interface which has one method:
`SendAuthRequest(username string, request string) (bool, error)`

A object called `DuoTwoFactor` is included here which uses DuoMobile through a
client object since it's one of the most common implementations.

In most cases, a call to request two factor auth will simply block the current
request until it completes or times out.  The user needs a way to receive
feedback letting them know they need to take action to complete the request --
this is usually provided by a client to the chat server.

In this case we ask for an object which satisfies the Prompter interface which has
one method:
`Speak(channel, message string) error`

# The Config File

The config file has the following format:

```yaml
commands:
  scary-command:
    2fa: true
    safe_rooms: system-ops
    safe_roles: system_administrators
```

A common way to reduce the repition if many commands need the same configuration
is to create "profiles" and use yaml's ability to include references:

```yaml
profiles:
  high-risk-commands: &high-risk
    owner: '@your_team'
    2fa: true
    safe_rooms:
      - system-ops
    safe_roles:
      - system_administrators
commands:
  scary-command:
    <<: *high-risk
```

**/

var (
	//nolint:stylecheck // not changing the error message to avoid breaking changes
	errInvalidGroup = errors.New("You are not in the correct group to run this command")
	//nolint:stylecheck // not changing the error message to avoid breaking changes
	errInvalidRoom = errors.New("You are not in the correct chatroom to run this command")
	//nolint:stylecheck // not changing the error message to avoid breaking changes
	errInvalidUser = errors.New("User not found")
)

// Validator is an object that takes care of checking security constraints.
type Validator struct {
	Config Constraints
	LDAP   UserGroupsGetter
	Auth   TwoFactorAuthorizer
}

// SecurityError is a wrapper to provide additional context about the error.
//
//nolint:revive // stuttering will not be addressed to avoid breaking changes
type SecurityError struct {
	Err     error
	Message string
}

// Error returns the message string with more information.
func (s *SecurityError) Error() string {
	return fmt.Sprintf("%s. %s", s.Err.Error(), s.Message)
}

// Unwrap the underlying error.
func (s *SecurityError) Unwrap() error {
	return s.Err
}

// UserGroupsGetter wraps the operations we're using from LDAP so we can easily create mock
// dependencies to use for testing.
type UserGroupsGetter interface {
	GetGroupsOfUser(username string) ([]string, error)
}

// Prompter is a interface to an object which can display a message to the user before
// sending a two factor auth request.
type Prompter interface {
	Speak(channel, message string) error
}

// IsRequestAuthorized validates that the given command meets the security constraints for a given command.
func (v *Validator) IsRequestAuthorized(user, room, command string,
	twoFactorPrompt Prompter) (bool, *SecurityError) {
	var safe bool
	var err error

	cmd, ok := v.Config.Commands[command]
	// if no config for command exists, then we pass
	if !ok {
		return true, nil
	}

	// valid rooms
	safe, err = v.IsValidRoom(room, cmd)
	if !safe {
		return false, &SecurityError{err, fmt.Sprintf("Valid room(s): %s", strings.Join(cmd.SafeRooms, ", "))}
	}

	// role based access
	safe, err = v.IsValidRole(user, cmd)
	if !safe {
		return false, &SecurityError{err, fmt.Sprintf("Valid role(s): %s", strings.Join(cmd.SafeRoles, ", "))}
	}

	// do two factor auth
	if cmd.Require2fa {
		ok, err := v.DoTwoFactorAuth(user, room, command, twoFactorPrompt)
		if err != nil || !ok {
			return false, &SecurityError{err, "Two factor auth failed"}
		}
	}

	return true, nil
}

// IsValidRole checks the LDAP roles of the given user.
func (v *Validator) IsValidRole(user string, cmd Command) (bool, error) {
	if len(cmd.SafeRoles) == 0 {
		return true, nil
	}
	validGroup := false

	groupsHash := make(map[string]bool, len(cmd.SafeRoles))
	for _, safe := range cmd.SafeRoles {
		groupsHash[safe] = true
	}

	groups, err := v.LDAP.GetGroupsOfUser(user)
	if err != nil {
		return false, err
	}
	for _, g := range groups {
		if ok := groupsHash[g]; ok {
			validGroup = true
		}
	}

	if !validGroup {
		return false, errInvalidGroup
	}

	return true, nil
}

// IsValidRoom checks the chatroom given.
func (v *Validator) IsValidRoom(room string, cmd Command) (bool, error) {
	if len(cmd.SafeRooms) == 0 {
		return true, nil
	}

	validRoom := false
	for _, safe := range cmd.SafeRooms {
		if room == safe || room == fmt.Sprintf("#%s", safe) {
			validRoom = true
		}
	}

	if !validRoom {
		return false, errInvalidRoom
	}

	return true, nil
}

// DoTwoFactorAuth performs a duo authentication requests in the context of a slack chatroom.
func (v *Validator) DoTwoFactorAuth(username, channel, command string, prompt Prompter) (bool, error) {
	resp, err := v.Auth.SendAuthRequest(username, command)
	if err != nil {
		return false, err
	}
	_ = prompt.Speak(channel, resp.Message)
	return v.Auth.CheckStatus(resp.Token)
}
