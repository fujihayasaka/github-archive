package models

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const MysqlDateTimeFormat = "2006-01-02 15:04:05"

// NullMysqlDateTime wraps sql.NullTime so that it can be (un)marshaled using the Mysql datetime format while allowing nil/null values
type NullMysqlDateTime struct {
	sql.NullTime
}

func NullMysqlDateTimeFromTime(t time.Time) NullMysqlDateTime {
	return NullMysqlDateTime{NullTime: sql.NullTime{Valid: true, Time: t}}
}

func (v NullMysqlDateTime) MarshalJSON() ([]byte, error) {
	if v.Valid {
		return []byte(fmt.Sprintf("\"%s\"", v.Time.Format(MysqlDateTimeFormat))), nil
	} else {
		return json.Marshal(nil)
	}
}

func (v *NullMysqlDateTime) UnmarshalJSON(data []byte) error {
	var x *string
	if err := json.Unmarshal(data, &x); err != nil {
		return errors.WithStack(err)
	}

	if x != nil {
		t, err := time.Parse(MysqlDateTimeFormat, *x)
		if err != nil {
			return errors.WithStack(err)
		}
		v.Valid = true
		v.Time = t
	} else {
		v.Valid = false
	}
	return nil
}

func (v NullMysqlDateTime) ToProto() *timestamppb.Timestamp {
	if v.Valid {
		return timestamppb.New(v.Time)
	}
	return nil
}
