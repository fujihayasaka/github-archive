package types

import (
	"time"

	"github.com/twitchtv/twirp"

	"github.com/github/spokes-proto/gen/go/v1/types"
)

func NewAttribution(name, email []byte, date time.Time) *Attribution {
	return &Attribution{
		Name:  name,
		Email: email,
		Date:  types.NewTimestamp(date),
	}
}

func hasNonCrud(value []byte) bool {
	for _, b := range value {
		if !(b < 040 || b == ',' || b == ':' || b == ';' || b == '<' || b == '>' || b == '"' || b == '\\' || b == '\'') {
			return true
		}
	}

	return false
}

func (a *Attribution) Validate() error {
	if a == nil {
		return nil
	}

	// Name
	name := a.GetName()
	if len(name) == 0 {
		return twirp.RequiredArgumentError("attribution.name")
	}

	if !hasNonCrud(name) {
		return twirp.InvalidArgumentError("attribution.name", "consists only of disallowed characters")
	}

	// Email
	email := a.GetEmail()
	if len(email) == 0 {
		return twirp.RequiredArgumentError("attribution.email")
	}

	if !hasNonCrud(email) {
		return twirp.InvalidArgumentError("attribution.email", "consists only of disallowed characters")
	}

	// Date
	date := a.GetDate()
	if date == nil {
		return twirp.RequiredArgumentError("attribution.date")
	}

	if err := date.ValidateGit(); err != nil {
		return err
	}

	return nil
}
