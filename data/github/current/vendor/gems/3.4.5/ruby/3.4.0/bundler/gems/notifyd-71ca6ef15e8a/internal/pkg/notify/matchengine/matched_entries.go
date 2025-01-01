package matchengine

import (
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

// NullString represents a string that can be null.
type NullString string

// MatchedEntry represents a matched entry.
type MatchedEntry struct {
	// RefID is the ID of the MetaSubscription for the match entry
	RefID     int64      `db:"ref_id"` // we need alias for this field
	UserID    int64      `db:"user_id"`
	Reason    string     `db:"reason"`
	Attribute NullString `db:"attribute"`
	Value     NullString `db:"value"`
	MatchRule NullString `db:"match_rule"`
	Channels  dto.ChannelsMap
}

// IsEmpty checks whether a MatchedEntry is empty.
func (m MatchedEntry) IsEmpty() bool {
	return m.Attribute == "" && m.MatchRule == "" && m.Value == ""
}

// Scan implements the sql.Scanner interface.
func (s *NullString) Scan(value interface{}) error {
	if value == nil {
		*s = ""
		return nil
	}
	strVal, ok := value.([]byte)
	if !ok {
		return errors.New("Column is not a string")
	}
	*s = NullString(strVal)
	return nil
}
