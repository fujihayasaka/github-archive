package model

import (
	"testing"
	"time"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/model"
)

func TestConfigerParseSchedule(t *testing.T) {
	suite.Run(t, new(scheduleParserTestSuite))
}

type scheduleParserTestSuite struct {
	suite.Suite
}

func (s *scheduleParserTestSuite) TestScheduleParserNext() {
	sch, err := s.parseExpression("*/10 * * * *")
	s.Assert().NoError(err)
	base := time.Date(2016, time.August, 15, 0, 0, 0, 0, time.UTC)
	next := sch.Next(base)
	s.Assert().Equal(time.Date(2016, time.August, 15, 0, 10, 0, 0, time.UTC), next)
}

func (s *scheduleParserTestSuite) TestScheduleParserNext_MaxFrequency() {
	sch, err := s.parseExpression("*/4 * * * *")
	s.Assert().NoError(err)
	base := time.Date(2016, time.August, 15, 0, 0, 0, 0, time.UTC)
	next := sch.Next(base)
	s.Assert().Equal(time.Date(2016, time.August, 15, 0, 5, 0, 0, time.UTC), next)
}

func (s *scheduleParserTestSuite) TestScheduleParserNextN() {
	sch, err := s.parseExpression("* * * * *")
	s.Assert().NoError(err)
	base := time.Date(2016, time.August, 15, 0, 0, 0, 0, time.UTC)
	for i, next := range sch.NextN(base, 5) {
		s.Assert().Equal(time.Date(2016, time.August, 15, 0, i+1, 0, 0, time.UTC), next)
	}
}

func (s *scheduleParserTestSuite) TestPosixOnlySupport() {
	tt := []struct {
		exp       string
		supported bool
	}{
		{"* * * * *", true},
		{"*/15 * * * *", true},
		{"1,15 * * * *", true},
		{"", false},
		{"@daily", false},
		{"@every 1h30m", false},
		{"0 0/15 * * Jul", false},
		{"0 30 08 ? Jul Sun", false},
	}
	for _, t := range tt {
		_, err := s.parseExpression(t.exp)
		if t.supported {
			s.Assert().NoErrorf(err, `Expected "%s" to not result in error`, t.exp)
		} else {
			s.Assert().Errorf(err, `Expected "%s" to result in error`, t.exp)
		}
	}
}

func (s *scheduleParserTestSuite) parseExpression(exp string) (Schedule, error) {
	return NewScheduleParser().Parse(&model.OnSchedule{
		Expression: exp,
	})
}
