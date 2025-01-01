package models

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/pkg/errors"
)

const (
	HoursInDay      = 24
	HoursInYear     = 8760
	HoursInLeapYear = 8784
)

type UsageTime struct {
	time.Time
}

// store date time as unix milli int64 in cosmos. this allows simple sorting and avoids formating errors
func (t *UsageTime) MarshalJSON() ([]byte, error) {
	return []byte(strconv.FormatInt(t.UTC().UnixMilli(), 10)), nil
}

func (t *UsageTime) UnmarshalJSON(data []byte) error {
	millis, err := strconv.ParseInt(string(data), 10, 64)
	if err != nil {
		return errors.Wrap(err, "failed to parse json time")
	}
	*t = fromUnixMilli(millis)
	return nil
}

func (t *UsageTime) GetFormattedDateForPeriod(period proto.BillingPeriod) *UsageTime {
	zerodOutTime := NewUsageTimeFromTime(time.Time{})

	switch period {
	case proto.BillingPeriod_Hourly:
		return NewUsageTimeFromTime(zerodOutTime.Time).WithYear(int64(t.Year())).WithMonthInt(int64(t.Month())).WithDay(t.Day()).WithHour(t.Hour()).WithMinute(t.Minute())
	case proto.BillingPeriod_Daily:
		return NewUsageTimeFromTime(zerodOutTime.Time).WithYear(int64(t.Year())).WithMonthInt(int64(t.Month())).WithDay(t.Day()).WithHour(t.Hour())
	case proto.BillingPeriod_Monthly:
		return NewUsageTimeFromTime(zerodOutTime.Time).WithYear(int64(t.Year())).WithMonthInt(int64(t.Month())).WithDay(t.Day())
	case proto.BillingPeriod_Yearly:
		return NewUsageTimeFromTime(zerodOutTime.Time).WithYear(int64(t.Year())).WithMonthInt(int64(t.Month()))
	default:
		return NewUsageTimeFromTime(t.Time)
	}
}

func fromUnixMilli(timestamp int64) UsageTime {
	return UsageTime{
		time.Unix(0, timestamp*int64(time.Millisecond)).UTC(),
	}
}

func NewUsageTimeFromUnixMilli(unixMilli int64) UsageTime {
	return fromUnixMilli(unixMilli)
}

func NewUsageTimeFromProto(unix int64) *UsageTime {
	return &UsageTime{
		Time: time.Unix(unix, 0).UTC(),
	}
}

func NewUsageTimeFromTime(t time.Time) *UsageTime {
	return &UsageTime{Time: t}
}

func NewUsageTime() *UsageTime {
	return NewUsageTimeFromTime(time.Time{})
}

func (t *UsageTime) AddDay(i int) *UsageTime {
	return NewUsageTimeFromTime(t.Time.AddDate(0, 0, i))
}

func (t *UsageTime) WithYear(year int64) *UsageTime {
	// Check if the year is within the bounds of int
	convertYear := ConvertYear(year)
	return NewUsageTimeFromTime(time.Date(int(convertYear), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// ConvertYear safely converts an int64 year to int with bounds checking.
func ConvertYear(year int64) int {
	if year < math.MinInt32 || year > math.MaxInt32 {
		return 0
	}
	return int(year)
}

func (t *UsageTime) WithMonthInt(month int64) *UsageTime {
	if month == 0 {
		month = 1
	}
	// Ensure the month is within the valid range [1, 12]
	if month < 1 || month > 12 {
		month = 1
	}
	return NewUsageTimeFromTime(time.Date(t.Year(), time.Month(month), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

func (t *UsageTime) WithMonth(month time.Month) *UsageTime {
	// Ensure the month is within the valid range [1, 12]
	if month < time.January || month > time.December {
		month = time.January
	}
	return NewUsageTimeFromTime(time.Date(t.Year(), month, t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// WithDay returns a new UsageTime with the day set to the given value.
// Note: If the value is 0, it will be set to 1, i.e this will only set dates in the month initialized.
func (t *UsageTime) WithDay(day int) *UsageTime {
	if day == 0 {
		day = 1
	}
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), day, t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}
func (t *UsageTime) WithHour(hour int) *UsageTime {
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), t.Day(), hour, t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}
func (t *UsageTime) WithMinute(minute int) *UsageTime {
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), minute, t.Second(), t.Nanosecond(), time.UTC))
}
func (t *UsageTime) WithSecond(second int) *UsageTime {
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), second, t.Nanosecond(), time.UTC))
}
func (t *UsageTime) WithNanosecond(nanosecond int) *UsageTime {
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), nanosecond, time.UTC))
}

func (t *UsageTime) Add(duration time.Duration) *UsageTime {
	return NewUsageTimeFromTime(t.Time.Add(duration))
}

func (u UsageTime) ToPartitionKey(t ActiveType) string {
	year, month, day := u.Date()
	hour := u.Hour()

	var s strings.Builder

	s.WriteString(fmt.Sprint(year))
	if t != Yearly {
		s.WriteString(PartitionKeyDelimiter)
		s.WriteString(fmt.Sprintf("%d", month))
		if t != Monthly {
			s.WriteString(PartitionKeyDelimiter)
			s.WriteString(fmt.Sprint(day))
			if t == Hourly {
				s.WriteString(PartitionKeyDelimiter)
				s.WriteString(fmt.Sprint(hour))
			}
		}
	}

	return s.String()
}

var UtcNow func() time.Time

func UTCNow() *UsageTime {
	if UtcNow == nil {
		UtcNow = func() time.Time { return time.Now().UTC() }
	}
	return NewUsageTimeFromTime(UtcNow())
}

func (u *UsageTime) BillableDaysInMonth() int {
	return time.Date(u.Year(), time.Month(u.Month()+1), 0, 0, 0, 0, 0, time.UTC).Day()
}

// Returns the last day of the month. Examples:
// January  => 31
// February => 28
// April		=> 30
func (u *UsageTime) LastDayOfTheMonth() int {
	nextMonth := u.AddDate(0, 1, -u.Day()+1)
	return nextMonth.Add(-24 * time.Hour).Day()
}

// Returns the number of days remaining in the month, including the current day. Examples:
// January 1st	=> 31
// January 15th	=> 17
// January 31st	=> 1
func (u *UsageTime) RemainingDaysInMonth() int {
	// Add 1 to the remaining days in the month to account for the current day.
	return u.LastDayOfTheMonth() - u.Day() + 1
}

func (u *UsageTime) BillableHoursThroughEndOf(period ActiveType) float64 {
	calcDuration := func(current time.Time, endOf time.Time) float64 {
		duration := endOf.Sub(current.Truncate(time.Minute)) // we will not worry about seconds and nano seconds.
		return duration.Hours()
	}
	switch period {
	case Hourly:
		return calcDuration(u.Time, u.EndOfHour())
	case Daily:
		return calcDuration(u.Time, u.EndOfDay())
	case Monthly:
		return calcDuration(u.Time, u.EndOfMonth())
	case Yearly:
		return calcDuration(u.Time, u.EndOfYear())
	default:
		return 0
	}
}

// Returns the billable hours based on the period and the usage date in order to account for
// products that are billed per hour. For example, shared storage uses the watermark meter
// and the billable time may be fractional for the hour the usage is reported, but should be the full
// hour for future hours:
//
// { usageAt: 2023-01-01Z00:00:30, quantity: 1 } => 0.5 billable hours when requesting for 2023-01-01 00:00:00
// { usageAt: 2023-01-01Z00:00:30, quantity: 1 } => 1.0 billable hours when requesting for 2023-01-01 00:01:00
func (u *UsageTime) BillableHoursForUsageDate(period ActiveType, usageDate *UsageTime) float64 {
	switch period {
	case Hourly:
		if !u.StartOfHour().Equal(usageDate.StartOfHour()) {
			return 1.0
		}
	case Daily:
		if !u.StartOfDay().Equal(usageDate.StartOfDay()) {
			return 24.0
		}
	case Monthly:
		if !u.StartOfMonth().Equal(usageDate.StartOfMonth()) {
			startOfMonth := NewUsageTimeFromTime(usageDate.StartOfMonth())
			endOfMonth := NewUsageTimeFromTime(usageDate.EndOfMonth())
			return startOfMonth.BillableHoursBetween(endOfMonth)
		}
	case Yearly:
		if u.Year() != usageDate.Year() {
			startOfYear := NewUsageTimeFromTime(usageDate.StartOfYear())
			endOfYear := NewUsageTimeFromTime(usageDate.EndOfYear())
			return startOfYear.BillableHoursBetween(endOfYear)
		}
	}

	return u.BillableHoursThroughEndOf(period)
}

func (u *UsageTime) EndOfYear() time.Time {
	return time.Date(u.Year()+1, 1, 1, 0, 0, 0, 0, time.UTC)
}
func (u *UsageTime) EndOfMonth() time.Time {
	return time.Date(u.Year(), time.Month(u.Month()+1), 1, 0, 0, 0, 0, time.UTC)
}
func (u *UsageTime) EndOfDay() time.Time {
	return time.Date(u.Year(), u.Month(), u.Day()+1, 0, 0, 0, 0, time.UTC)
}
func (u *UsageTime) EndOfHour() time.Time {
	return time.Date(u.Year(), u.Month(), u.Day(), u.Hour()+1, 0, 0, 0, time.UTC)
}
func (u *UsageTime) StartOfHour() time.Time {
	return time.Date(u.Year(), u.Month(), u.Day(), u.Hour(), 0, 0, 0, time.UTC)
}
func (u *UsageTime) StartOfDay() time.Time {
	return time.Date(u.Year(), u.Month(), u.Day(), 0, 0, 0, 0, time.UTC)
}
func (u *UsageTime) StartOfMonth() time.Time {
	return time.Date(u.Year(), u.Month(), 1, 0, 0, 0, 0, time.UTC)
}
func (u *UsageTime) StartOfYear() time.Time {
	return time.Date(u.Year(), 1, 1, 0, 0, 0, 0, time.UTC)
}

func (u *UsageTime) BillableHoursBetween(other *UsageTime) float64 {
	// get the very first nano second of the given usage time
	// this lets us get inclusive hours for billing

	duration := u.Truncate(time.Minute).Sub(other.Truncate(time.Minute))
	return math.Abs(duration.Hours())
}

func (u *UsageTime) IsInSameYearAndMonth(other *UsageTime) bool {
	return u.Year() == other.Year() && u.Month() == other.Month()
}
