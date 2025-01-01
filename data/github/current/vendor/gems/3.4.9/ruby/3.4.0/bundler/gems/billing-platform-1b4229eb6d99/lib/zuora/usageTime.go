package zuora

import (
	"fmt"
	"time"

	"github.com/pkg/errors"
)

var dateFormat = "2006-01-02"
var dateTimeFormat = "2006-01-02T15:04:05-0700"

type ZuoraUsageDate struct {
	time.Time
}

func (t *ZuoraUsageDate) MarshalJSON() ([]byte, error) {
	return []byte(t.Time.Format(dateFormat)), nil
}

func (t *ZuoraUsageDate) UnmarshalJSON(b []byte) error {
	date, err := time.Parse(fmt.Sprintf(`"%s"`, dateFormat), string(b))
	if err != nil {
		return errors.Wrap(err, "failed to parse date")
	}
	t.Time = date
	return nil
}

type ZuoraUsageDateTime struct {
	time.Time
}

func (t *ZuoraUsageDateTime) UnmarshalJSON(b []byte) error {
	date, err := time.Parse(fmt.Sprintf(`"%s"`, dateTimeFormat), string(b))
	if err != nil {
		return errors.Wrap(err, "failed to parse date")
	}
	t.Time = date
	return nil
}

func (t *ZuoraUsageDateTime) MarshalJSON() ([]byte, error) {
	return []byte(t.Time.Format(fmt.Sprintf(`"%s"`, dateTimeFormat))), nil
}
