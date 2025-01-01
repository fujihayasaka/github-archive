package gormext

import (
	"time"

	"github.com/SamuelTissot/sqltime"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func ConvertTime(t *time.Time) *sqltime.Time {
	if t == nil || t.IsZero() {
		return nil
	}

	truncTime := t.In(sqltime.DatabaseLocation).Truncate(sqltime.TruncateOff)
	return &sqltime.Time{Time: truncTime}
}

func ConvertPBTime(pbTime *timestamppb.Timestamp) *sqltime.Time {
	if pbTime == nil {
		return nil
	}

	t := pbTime.AsTime()

	return ConvertTime(&t)
}
