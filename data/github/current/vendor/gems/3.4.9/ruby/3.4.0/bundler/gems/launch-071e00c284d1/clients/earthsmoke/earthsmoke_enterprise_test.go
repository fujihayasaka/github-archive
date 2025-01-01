package earthsmoke

import (
	"context"
	"encoding/base64"
	"testing"

	"github.com/stretchr/testify/suite"

	"github.com/github/launch/workflowbuild"
)

func TestEarthsmokeEnterprise(t *testing.T) {
	suite.Run(t, new(earthsmokeEnterpriseTestSuite))
}

type earthsmokeEnterpriseTestSuite struct {
	suite.Suite
}

func (s *earthsmokeEnterpriseTestSuite) TestEnterpriseDecryptor() {
	secret := "Shhh!"
	encodedSecret := base64.StdEncoding.EncodeToString([]byte(secret))

	decryptor := NewEnterpriseDecryptor()
	value, valid, err := decryptor.DecryptSecretValue(context.Background(), encodedSecret, "", workflowbuild.ActionsSecretSource)
	s.NoError(err)
	s.Assert().True(valid)
	s.Equal(secret, value)
}
