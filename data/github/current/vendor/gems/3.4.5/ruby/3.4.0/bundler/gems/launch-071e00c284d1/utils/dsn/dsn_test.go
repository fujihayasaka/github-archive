package dsn

import (
	"testing"

	"github.com/stretchr/testify/suite"
)

const (
	testDSNBase = "user:pass@tcp(host:3306)/schema"
)

type dsnTestSuite struct {
	suite.Suite
}

func TestDSNTestSuite(t *testing.T) {
	suite.Run(t, new(dsnTestSuite))
}

func (s *dsnTestSuite) TestWithNoExistingAttributes() {
	dsn := testDSNBase
	out, err := WithAttribute(dsn, "interpolateParams", "true")
	s.NoError(err)
	s.Equal(dsn+"?interpolateParams=true", out)
}

func (s *dsnTestSuite) TestWithExistingAttributes() {
	dsn := testDSNBase + "?parseTime=true"
	out, err := WithAttribute(dsn, "interpolateParams", "true")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?interpolateParams=true&parseTime=true", out)
}

func (s *dsnTestSuite) TestWithTrailingQuestionMark() {
	dsn := testDSNBase + "?"
	out, err := WithAttribute(dsn, "interpolateParams", "true")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?interpolateParams=true", out)
}

func (s *dsnTestSuite) TestReplacesAttribute() {
	dsn := testDSNBase + "?interpolateParams=false"
	out, err := WithAttribute(dsn, "interpolateParams", "true")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?interpolateParams=true", out)
}

func (s *dsnTestSuite) TestWithEncodedKey() {
	dsn := testDSNBase
	out, err := WithAttribute(dsn, "foo@bar", "value")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?foo%40bar=value", out)
}

func (s *dsnTestSuite) TestEncodedValue() {
	dsn := testDSNBase + "?interpolateParams=false"
	out, err := WithAttribute(dsn, "key", "foo@bar")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?interpolateParams=false&key=foo%40bar", out)
}

func (s *dsnTestSuite) TestWithEncodedValue() {
	dsn := testDSNBase + "?interpolateParams=false"
	out, err := WithAttribute(dsn, "key", "foo@bar")
	s.NoError(err)
	s.Equal("user:pass@tcp(host:3306)/schema?interpolateParams=false&key=foo%40bar", out)
}

func (s *dsnTestSuite) TestWithQuestionMarkInPassword() {
	dsn := "user:pa?s@tcp(host:3306)/schema?interpolateParams=false"
	out, err := WithAttribute(dsn, "key", "foo@bar")
	s.NoError(err)
	s.Equal("user:pa?s@tcp(host:3306)/schema?interpolateParams=false&key=foo%40bar", out)
}
