package managedanalyses

import (
	"math/rand"
	"time"
)

const (
	minutesInADay = 60 * 24
	threeAM       = 60 * 3
)

func NewScheduler(skipMidnight bool) *Scheduler {
	return &Scheduler{
		skipMidnight: skipMidnight,
		randIntn:     rand.Intn,
	}
}

func NewDeterministicScheduler(skipMidnight bool, randIntn func(int) int) *Scheduler {
	return &Scheduler{
		skipMidnight: skipMidnight,
		randIntn:     randIntn,
	}
}

type Scheduler struct {
	skipMidnight bool

	randIntn func(int) int
}

func (s *Scheduler) GetRandomScheduleTime() time.Time {
	now := time.Now().UTC()
	year, month, day := now.Date()

	// Get the day
	day += s.randIntn(7)

	// Get the schedule time
	var minute int
	if s.skipMidnight {
		// We don't want to schedule anything between 00:00 and 03:00
		for ; minute <= threeAM; minute = s.randIntn(minutesInADay) {
		}
	} else {
		minute = s.randIntn(minutesInADay)
	}

	// Assemble the date
	date := time.Date(year, month, day, 0, minute, 0, 0, time.UTC)
	date = GetNextScheduleTime(date) // This makes sure that the date is not in the past
	return date
}

func GetNextScheduleTime(current time.Time) time.Time {
	next := current
	for {
		if next.After(time.Now()) {
			break
		}
		next = next.AddDate(0, 0, 7)
	}

	return next
}
