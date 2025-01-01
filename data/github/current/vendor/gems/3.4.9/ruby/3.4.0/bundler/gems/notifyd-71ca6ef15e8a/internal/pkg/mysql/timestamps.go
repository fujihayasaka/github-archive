package mysql

import (
	"time"

	"github.com/benbjohnson/clock"
)

/*
Timestamps is a common struct and behaviour around timestamp columns in database tables.

If your struct represents a row in a table with the columns `created_at` and `update_at`,
you can embed the Timestamps struct to get the `CreatedAt` and `UpdatedAt` fields and
the UpdateTimestamps() method.

Example:

	type MyData struct {
	  ID int64 `db:id`
	  mysql.Timestamps
	}

m := MyData{}
m.UpdateTimestamps(clock)
*/
type Timestamps struct {
	CreatedAt time.Time `db:"created_at" json:"-"`
	UpdatedAt time.Time `db:"updated_at" json:"-"`
}

// NewTimestamps creates a new Timestamps struct with the current time using Clock.
func NewTimestamps(clk clock.Clock) Timestamps {
	currentTime := clk.Now().Truncate(time.Second).In(time.UTC)
	return Timestamps{
		CreatedAt: currentTime,
		UpdatedAt: currentTime,
	}
}

// UpdateTimestamps is a hook used when saving any data structure that uses the Timestamp struct so
// that they also trigger updating the timestamps as needed:
//
// - For created entries it sets the created_at and updated_at at the same value
// - For existing entries it only changes updated_at
func (t *Timestamps) UpdateTimestamps(clk clock.Clock) {
	now := clk.Now().Truncate(time.Second).In(time.UTC)

	if t.CreatedAt.IsZero() {
		t.CreatedAt = now
	}
	t.UpdatedAt = now
}
