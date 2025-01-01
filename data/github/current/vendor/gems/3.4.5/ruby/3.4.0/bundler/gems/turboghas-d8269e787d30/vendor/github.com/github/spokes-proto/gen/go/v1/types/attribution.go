package types

import (
	"time"
)

func NewAttribution(name, email string, date time.Time) *Attribution {
	return &Attribution{
		Name:  name,
		Email: email,
		Date:  NewTimestamp(date),
	}
}
