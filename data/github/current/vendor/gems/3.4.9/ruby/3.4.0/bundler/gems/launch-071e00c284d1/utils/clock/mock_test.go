package clock

import (
	"testing"
	"time"

	"github.com/stretchr/testify/suite"
)

type clockSuite struct {
	suite.Suite
	mock *Mock
}

func TestMockClock(t *testing.T) {
	suite.Run(t, new(clockSuite))
}

func (s *clockSuite) SetupTest() {
	s.mock = NewMock(1000)
}

func (s *clockSuite) Test_Add() {
	startTime := s.mock.Now()

	s.mock.Add(time.Minute)

	s.Equal(time.Minute, s.mock.Now().Sub(startTime))
	s.Equal(time.Minute, s.mock.Since(startTime))
}

func (s *clockSuite) Test_Ticker() {
	ticker := s.mock.NewTicker(time.Second)

	s.mock.Add(time.Minute)
	count := consumeTicks(ticker)

	s.Equal(60, count)
}

func (s *clockSuite) Test_Ticker_Remainders() {
	ticker := s.mock.NewTicker(time.Minute)

	s.mock.Add(20 * time.Second)
	s.Equal(0, consumeTicks(ticker))

	s.mock.Add(20 * time.Second)
	s.Equal(0, consumeTicks(ticker))

	s.mock.Add(25 * time.Second)
	s.Equal(1, consumeTicks(ticker))

	s.mock.Add(115 * time.Second)
	s.Equal(2, consumeTicks(ticker))
}

func (s *clockSuite) Test_Multiple_Tickers() {
	ticker1 := s.mock.NewTicker(time.Second)
	ticker2 := s.mock.NewTicker(5 * time.Second)

	s.mock.Add(time.Minute)

	s.Equal(60, consumeTicks(ticker1))
	s.Equal(12, consumeTicks(ticker2))
}

func consumeTicks(t Ticker) int {
	count := 0
	for {
		select {
		case <-t.C():
			count++
		default:
			return count
		}
	}
}
