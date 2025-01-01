package model

import (
	"time"

	"github.com/robfig/cron"

	"github.com/github/launch/model"
)

type ScheduleParser interface {
	Parse(on *model.OnSchedule) (Schedule, error)
	ParseExpression(expression string) (Schedule, error)
}

const MaxScheduleFrequency = 5 * time.Minute

func NewScheduleParser() ScheduleParser {
	return &scheduleParser{
		c: cron.NewParser(
			cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow,
		),
	}
}

// scheduleParser is a thin wrapper around cron.Parser
type scheduleParser struct {
	c cron.Parser
}

func (p *scheduleParser) Parse(on *model.OnSchedule) (Schedule, error) {
	s, err := p.c.Parse(on.Expression)
	if err != nil {
		return nil, err
	}
	return &schedule{
		s: s,
	}, nil
}

func (p *scheduleParser) ParseExpression(expression string) (Schedule, error) {
	return p.Parse(&model.OnSchedule{
		Expression: expression,
	})
}

type Schedule interface {
	Next(t time.Time) time.Time
	// sooner to later
	NextN(t time.Time, n int) []time.Time
}

type schedule struct {
	s cron.Schedule
}

func (s *schedule) Next(t time.Time) time.Time {
	nextRun := s.s.Next(t)
	in5mins := t.Add(MaxScheduleFrequency)
	if nextRun.Before(in5mins) {
		nextRun = in5mins
	}
	return nextRun
}

func (s *schedule) NextN(t time.Time, n int) []time.Time {
	var times []time.Time
	next := t
	for i := 0; i < n; i++ {
		next = s.s.Next(next)
		times = append(times, next)
	}
	return times
}
