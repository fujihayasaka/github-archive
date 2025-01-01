package e2e

import (
	"net/http"
	"testing"

	twirpauth "github.com/github/go-twirp/client/auth"
	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/stretchr/testify/suite"
)

type AuthHmacE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestAuthHmacE2ETestSuite(t *testing.T) {
	t.Parallel()

	suite.Run(t, new(AuthHmacE2ETestSuite))
}

func (s *AuthHmacE2ETestSuite) Test_CustomerAPI_PassesWithCorrectHMAC() {
	resp, err := s.customerTwirpClient.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})

	s.Require().NoError(err)
	s.Require().NotNil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_CustomerAPI_FailsWithInvalidHMAC() {
	authClient, err := twirpauth.NewRequestHMACSigner("invalid_hmac", &http.Client{})
	s.Require().NoError(err)

	clientWithInvalidHmac := imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, authClient)

	resp, err := clientWithInvalidHmac.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated: HMAC")
	s.Require().ErrorContains(err, "is invalid")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_CustomerAPI_FailsWithoutAuth() {
	clientWithInvalidHmac := imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithInvalidHmac.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated: no Request-HMAC provided")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_AdminAPI_PassesWithCorrectHMAC() {
	resp, err := s.adminTwirpClient.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})

	s.Require().NoError(err)
	s.Require().NotNil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_AdminAPI_FailsWithInvalidHMAC() {
	authClient, err := twirpauth.NewRequestHMACSigner("invalid_hmac", &http.Client{})
	s.Require().NoError(err)

	clientWithInvalidHmac := adminapi.NewImageManagementAdminServiceProtobufClient(s.serverUrl, authClient)

	resp, err := clientWithInvalidHmac.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().ErrorContains(err, "twirp error unauthenticated: HMAC")
	s.Require().ErrorContains(err, "is invalid")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_AdminAPI_FailsWithoutAuth() {
	clientWithInvalidHmac := adminapi.NewImageManagementAdminServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithInvalidHmac.ListCuratedImageDefinitions(s.ctx, &adminapi.ListCuratedImageDefinitionsRequest{})
	s.Require().ErrorContains(err, "twirp error unauthenticated: no Request-HMAC provided")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_InternalAPI_PassesWithCorrectHMAC() {
	resp, err := s.internalTwirpClient.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{
			Source:  "Curated",
			Id:      7418451152,
			Version: "latest",
		},
	})
	s.Require().ErrorContains(err, "twirp error not_found: image definition is not found")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_InternalAPI_FailsWithInvalidHMAC() {
	authClient, err := twirpauth.NewRequestHMACSigner("invalid_hmac", &http.Client{})
	s.Require().NoError(err)

	clientWithInvalidHmac := internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, authClient)

	resp, err := clientWithInvalidHmac.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{
			Source:  "Curated",
			Id:      7418451152,
			Version: "latest",
		},
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated: HMAC")
	s.Require().ErrorContains(err, "is invalid")
	s.Require().Nil(resp)
}

func (s *AuthHmacE2ETestSuite) Test_InternalAPI_FailsWithoutAuth() {
	clientWithInvalidHmac := internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithInvalidHmac.GetImageReference(s.ctx, &internalapi.GetImageReferenceRequest{
		ImageKey: &internalapi.ImageKey{
			Source:  "Curated",
			Id:      7418451152,
			Version: "latest",
		},
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated: no Request-HMAC provided")
	s.Require().Nil(resp)
}
