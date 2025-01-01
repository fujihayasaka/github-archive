package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/twirp/proto"
)

func Test_Defaults_are_properly_handled(t *testing.T) {
	objectUnderTest := NewUsageTime().WithYear(2023).WithMonthInt(0).WithDay(0)

	if objectUnderTest.Year() != 2023 {
		t.Error("Year should be 2023", objectUnderTest.Year())
		t.Fail()
	}

	if objectUnderTest.Month() != time.January {
		t.Error("Month should be January", objectUnderTest.Month())
		t.Fail()
	}

	if objectUnderTest.Day() != 1 {
		t.Error("Day should be 1", objectUnderTest.Day())
		t.Fail()
	}
}

func Test_ToPartitionKey(t *testing.T) {
	objectUnderTest := NewUsageTime().WithYear(2023).WithMonth(time.October).WithDay(11).WithHour(14).WithMinute(15).WithSecond(16).WithNanosecond(17)

	hh := objectUnderTest.ToPartitionKey(Hourly)
	if hh != "2023:10:11:14" {
		t.Error("hh Partition key should be 2023:10:11:14", hh)
		t.Fail()
	}

	dd := objectUnderTest.ToPartitionKey(Daily)
	if dd != "2023:10:11" {
		t.Error("dd Partition key should be 2023:10:11", dd)
		t.Fail()
	}

	m := objectUnderTest.ToPartitionKey(Monthly)
	if m != "2023:10" {
		t.Error("m Partition key should be 2023:10", m)
		t.Fail()
	}

	y := objectUnderTest.ToPartitionKey(Yearly)
	if y != "2023" {
		t.Error("y Partition key should be 2023", y)
		t.Fail()
	}

	zeroHour := objectUnderTest.WithHour(0).ToPartitionKey(Hourly)
	if zeroHour != "2023:10:11:0" {
		t.Error("zeroHour Partition key should be 2023:10:11:0", zeroHour)
		t.Fail()
	}

	lastHour := objectUnderTest.WithHour(23).ToPartitionKey(Hourly)
	if lastHour != "2023:10:11:23" {
		t.Error("lastHour Partition key should be 2023:10:11:23", lastHour)
		t.Fail()
	}

	firstDayOfMonth := objectUnderTest.WithDay(1).ToPartitionKey(Daily)
	if firstDayOfMonth != "2023:10:1" {
		t.Error("firstDayOfMonth Partition key should be 2023:10:1", firstDayOfMonth)
		t.Fail()
	}

	lastDayOfYear := objectUnderTest.WithMonth(time.December).WithDay(31).ToPartitionKey(Daily)
	if lastDayOfYear != "2023:12:31" {
		t.Error("lastDayOfYear Partition key should be 2023:12:31", lastDayOfYear)
		t.Fail()
	}
}

func Test_BillableDaysInMonth(t *testing.T) {
	tests := map[time.Month]int{
		time.January:   31,
		time.February:  28,
		time.March:     31,
		time.April:     30,
		time.May:       31,
		time.June:      30,
		time.July:      31,
		time.August:    31,
		time.September: 30,
		time.October:   31,
		time.November:  30,
		time.December:  31,
	}

	year := NewUsageTime().WithYear(2023)
	for month, expectedDays := range tests {
		t.Run(fmt.Sprintf("Billable Days Expected in %d == %d", month, expectedDays), func(t *testing.T) {
			// Setting a day of 10 to ensure that the day of the month doesn't affect the result
			results := year.WithMonth(month).WithDay(10).BillableDaysInMonth()
			if results != expectedDays {
				t.Error("Billable days should be", expectedDays, results)
				t.Fail()
			}
		})
	}
}

func Test_BillableDaysInMonth_LeapYear(t *testing.T) {
	year := NewUsageTime().WithYear(2020)
	results := year.WithMonth(time.February).BillableDaysInMonth()
	if results != 29 {
		t.Error("Billable days should be 29", results)
		t.Fail()
	}
}

func Test_BillableHoursThroughEndOf_ForAGivenDay(t *testing.T) {
	expectedHours := 24.0
	usageDate := NewUsageTime().WithYear(2013).WithMonth(1).WithDay(1).WithHour(9)
	for i := 0; i < HoursInDay; i++ {
		t.Run(fmt.Sprintf("Billable Hours Expected in day %f", expectedHours), func(t *testing.T) {
			results := usageDate.WithHour(i).BillableHoursThroughEndOf(Daily)
			if results != expectedHours {
				t.Error("Billable hours should be", expectedHours, results)
				t.Fail()
			}
			expectedHours--
		})
	}
}

func Test_BillableHoursThroughEndOf_ForAGivenMonth(t *testing.T) {
	tests := map[time.Month]float64{
		time.January:   744,
		time.February:  672,
		time.March:     744,
		time.April:     720,
		time.May:       744,
		time.June:      720,
		time.July:      744,
		time.August:    744,
		time.September: 720,
		time.October:   744,
		time.November:  720,
		time.December:  744,
	}

	year := NewUsageTime().WithYear(2023)
	for month, expectedHoursByMonth := range tests {
		yearWithMonth := year.WithMonth(month)
		expectedHours := expectedHoursByMonth
		daysInMonth := int(expectedHours) / HoursInDay
		for day := 1; day <= daysInMonth; day++ {
			dateWithDay := yearWithMonth.WithDay(day)
			t.Run(fmt.Sprintf("Billable Hours Expected in %d/%d == %f", month, day, expectedHours), func(t *testing.T) {
				results := dateWithDay.BillableHoursThroughEndOf(Monthly)
				if results != expectedHours {
					t.Error("Billable hours should be", expectedHours, results)
					t.Fail()
				}
				expectedHours -= HoursInDay
			})
		}
	}
}

func Test_BillableHoursForLeapYear(t *testing.T) {
	const leapYear int64 = 2020
	tests := map[time.Month]float64{
		time.February: 696,
	}

	year := NewUsageTime().WithYear(leapYear)
	for month, expectedHoursByMonth := range tests {
		expectedHours := expectedHoursByMonth
		daysInMonth := int(expectedHours) / HoursInDay
		withMonth := year.WithMonth(month)
		for i := 1; i <= daysInMonth; i++ {
			t.Run(fmt.Sprintf("Billable Hours Expected in %d/%d == %f", month, i, expectedHours), func(t *testing.T) {
				results := withMonth.WithDay(i).BillableHoursThroughEndOf(Monthly)
				if results != expectedHours {
					t.Error("Billable hours should be", expectedHours, results)
					t.Fail()
				}
				expectedHours -= HoursInDay
			})
		}
	}
}

func Test_BillableHoursForAllHoursInAmonth(t *testing.T) {
	tests := map[time.Month]float64{
		time.October: 744.0,
	}

	for month, expectedHoursByMonth := range tests {
		expectedHours := expectedHoursByMonth
		date := NewUsageTime().WithYear(2023).WithMonth(month).WithDay(1)

		var i float64 = 0
		for i < expectedHours {
			t.Run(fmt.Sprintf("Billable Hours Expected on %s in %f", date, expectedHours), func(t *testing.T) {
				eh := expectedHours
				results := date.BillableHoursThroughEndOf(Monthly)
				if results != eh {
					t.Error("Billable hours should be", eh, results)
					t.Fail()
				}
			})
			date = date.Add(time.Hour)
			expectedHours--
		}
	}
}

func Test_Fractional_BillableHoursForAllHoursInAmonth(t *testing.T) {

	date := NewUsageTime().WithYear(2023).WithMonth(time.October).WithDay(1)

	results := date.BillableHoursThroughEndOf(Monthly)
	if results != 744.0 {
		t.Error("Billable hours should be", 744.0, results)
		t.Fail()
	}

	results = date.WithMinute(1).BillableHoursThroughEndOf(Monthly)
	if results != 743.9833333333333 {
		t.Error("Billable hours should be", 743.9833333333333, results)
		t.Fail()
	}

	results = date.WithDay(16).WithHour(12).BillableHoursThroughEndOf(Monthly)
	if results != 372 {
		t.Error("Billable hours should be", 372, results)
		t.Fail()
	}

	results = date.WithHour(12).BillableHoursThroughEndOf(Daily)
	if results != 12 {
		t.Error("Billable hours should be", 12, results)
		t.Fail()
	}

	results = date.BillableHoursThroughEndOf(Hourly)
	if results != 1 {
		t.Error("Billable hours should be", 1, results)
		t.Fail()
	}

	results = date.WithMinute(21).BillableHoursThroughEndOf(Hourly)
	if results != 0.65 {
		t.Error("Billable hours should be", 0.65, results)
		t.Fail()
	}

	results = date.WithMinute(54).BillableHoursThroughEndOf(Hourly)
	if results != 0.1 {
		t.Error("Billable hours should be", 0.1, results)
		t.Fail()
	}
}

func Test_BillableHoursFor_AYear(t *testing.T) {
	tests := map[time.Month]float64{
		time.January:   744,
		time.February:  672,
		time.March:     744,
		time.April:     720,
		time.May:       744,
		time.June:      720,
		time.July:      744,
		time.August:    744,
		time.September: 720,
		time.October:   744,
		time.November:  720,
		time.December:  744,
	}

	orderedMonths := []time.Month{time.January, time.February, time.March, time.April, time.May, time.June, time.July, time.August, time.September, time.October, time.November, time.December}

	expectedHours := float64(HoursInYear)
	for _, month := range orderedMonths {
		expectedHoursByMonth := tests[month]
		t.Run(fmt.Sprintf("Billable Hours Expected in %s == %f", month, expectedHours), func(t *testing.T) {
			date := NewUsageTime().WithYear(2023).WithMonth(month).WithDay(1)
			results := date.BillableHoursThroughEndOf(Yearly)
			if results != expectedHours {
				t.Error("billable hours month should be", month, expectedHours, results)
				t.Fail()
			}
			expectedHours -= expectedHoursByMonth
		})
	}
}

func Test_BillableHoursBetween(t *testing.T) {
	startDate := NewUsageTime().WithYear(2020).WithMonth(time.January).WithDay(1)

	expectedHours := 1.0
	results := startDate.BillableHoursBetween(startDate.WithHour(1))
	if results != expectedHours {
		t.Error("billable hours month should be", expectedHours, results)
		t.Fail()
	}

	expectedHours = 0.5
	results = startDate.BillableHoursBetween(startDate.WithMinute(30))
	if results != expectedHours {
		t.Error("billable hours month should be", expectedHours, results)
		t.Fail()
	}

	expectedHours = 0.1
	results = startDate.BillableHoursBetween(startDate.WithMinute(6))
	if results != expectedHours {
		t.Error("billable hours month should be", expectedHours, results)
		t.Fail()
	}

	expectedHours = 744.0
	results = startDate.BillableHoursBetween(startDate.WithMonth(time.February))
	if results != expectedHours {
		t.Error("billable hours month should be", expectedHours, results)
		t.Fail()
	}
}

func Test_BillableHoursForUsageDate(t *testing.T) {
	january1st2021 := NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(1)
	january2nd2021 := NewUsageTime().WithYear(2021).WithMonth(time.January).WithDay(2)
	february1st2021 := NewUsageTime().WithYear(2021).WithMonth(time.February).WithDay(1)
	january1st2022 := NewUsageTime().WithYear(2022).WithMonth(time.January).WithDay(1)

	tests := []struct {
		name          string
		subject       *UsageTime
		usageDate     *UsageTime
		activeType    ActiveType
		expectedHours float64
	}{
		{"Hourly type returns full hour with whole amount ", january1st2021, january1st2021, Hourly, 1.0},
		{"Hourly type same hour", january1st2021.WithMinute(30), january1st2021, Hourly, 0.5},
		{"Hourly type different hour", january1st2021.WithMinute(30), january1st2021.WithHour(1), Hourly, 1.0},
		{"Hourly type different day", january1st2021.WithMinute(30), january2nd2021, Hourly, 1.0},
		{"Hourly type different month", january1st2021.WithMinute(30), february1st2021, Hourly, 1.0},
		{"Hourly type different year", january1st2021.WithMinute(30), january1st2022, Hourly, 1.0},

		{"Daily type returns full day with whole amount", january1st2021, january1st2021, Daily, 24.0},
		{"Daily type same hour", january1st2021.WithMinute(30), january1st2021, Daily, 23.5},
		{"Daily type different hour", january1st2021.WithMinute(30), january1st2021.WithHour(2), Daily, 23.5},
		{"Daily type different day", january1st2021.WithMinute(30), january2nd2021, Daily, 24.0},
		{"Daily type different month", january1st2021.WithMinute(30), february1st2021, Daily, 24.0},
		{"Daily type different year", january1st2021.WithMinute(30), january1st2022, Daily, 24.0},

		{"Monthly type returns full month when days match", january1st2021, january1st2021, Monthly, 744.0},
		{"Monthly type same hour", january1st2021.WithMinute(30), january1st2021, Monthly, 743.5},
		{"Monthly type different hour", january1st2021.WithMinute(30), january1st2021.WithHour(2), Monthly, 743.5},
		{"Monthly type different day", january1st2021.WithMinute(30), january2nd2021, Monthly, 743.5},
		{"Monthly type different month", january1st2021.WithMinute(30), february1st2021, Monthly, 672},
		{"Monthly type different year", january1st2021.WithMinute(30), january1st2022, Monthly, 744},

		{"Yearly type returns full year with whole amount", january1st2021, january1st2021, Yearly, 8760.0},
		{"Yearly type same hour", january1st2021.WithMinute(30), january1st2021, Yearly, 8759.5},
		{"Yearly type different hour", january1st2021.WithMinute(30), january1st2021.WithHour(2), Yearly, 8759.5},
		{"Yearly type different day", january1st2021.WithMinute(30), january2nd2021, Yearly, 8759.5},
		{"Yearly type different month", january1st2021.WithMinute(30), february1st2021, Yearly, 8759.5},
		{"Yearly type different year", january1st2021.WithMinute(30), january1st2022, Yearly, 8760.0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			hours := tt.subject.BillableHoursForUsageDate(tt.activeType, tt.usageDate)
			if hours != tt.expectedHours {
				t.Errorf("expected billable hours to be %f, got %f", tt.expectedHours, hours)
			}
		})
	}
}

func Test_GetFormattedDateForPeriod(t *testing.T) {
	inputDate := NewUsageTime().WithYear(2023).WithMonth(time.January).WithDay(1).WithHour(1).WithMinute(1).WithSecond(1)

	tests := []struct {
		period proto.BillingPeriod
	}{
		{proto.BillingPeriod_Hourly},
		{proto.BillingPeriod_Daily},
		{proto.BillingPeriod_Monthly},
		{proto.BillingPeriod_Yearly},
		{proto.BillingPeriod_Unspecified},
	}

	for _, tt := range tests {
		t.Run(tt.period.String(), func(t *testing.T) {
			var expectedDate time.Time
			switch tt.period {
			case proto.BillingPeriod_Hourly:
				expectedDate = NewUsageTime().WithYear(2023).WithMonth(time.January).WithDay(1).WithHour(1).WithMinute(1).Time
			case proto.BillingPeriod_Daily:
				expectedDate = NewUsageTime().WithYear(2023).WithMonth(time.January).WithDay(1).WithHour(1).Time
			case proto.BillingPeriod_Monthly:
				expectedDate = NewUsageTime().WithYear(2023).WithMonth(time.January).WithDay(1).Time
			case proto.BillingPeriod_Yearly:
				expectedDate = NewUsageTime().WithYear(2023).WithMonth(time.January).Time
			case proto.BillingPeriod_Unspecified:
				expectedDate = inputDate.Time
			}

			formattedDate := inputDate.GetFormattedDateForPeriod(tt.period)
			if formattedDate.Time != expectedDate {
				t.Error("formatted date should be", expectedDate, "but got", formattedDate.Time)
				t.Fail()
			}
		})
	}
}
