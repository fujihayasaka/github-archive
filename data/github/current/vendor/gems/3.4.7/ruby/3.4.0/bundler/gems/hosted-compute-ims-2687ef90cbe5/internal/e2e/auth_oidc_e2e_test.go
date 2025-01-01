package e2e

import (
	"net/http"
	"testing"

	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	sharedapi "github.com/github/hosted-compute-ims/gen/twirp/go/shared"
	"github.com/stretchr/testify/suite"
	"github.com/twitchtv/twirp"
)

type AuthOidcE2ETestSuite struct {
	BaseE2ETestSuite
}

func TestOidcAuthE2ETestSuite(t *testing.T) {
	if !isOidcAuthAvailable() {
		// skip auth tests when running e2e against real environments (lab, production)
		// because generating vssf auth token for real environment is tricky
		t.Skip()
	}

	t.Parallel()

	suite.Run(t, new(AuthOidcE2ETestSuite))
}

func (s *AuthOidcE2ETestSuite) Test_InternalApi_FailsWithoutOidc() {
	ctx, err := twirp.WithHTTPRequestHeaders(s.ctx, http.Header{"Authorization": []string{""}})
	s.Require().NoError(err)

	clientWithoutAuth := internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithoutAuth.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{})
	s.Require().ErrorContains(err, "twirp error unauthenticated")
	s.Require().ErrorContains(err, "no bearer token provided")
	s.Require().Nil(resp)
}

func (s *AuthOidcE2ETestSuite) Test_InternalApi_FailsWithIncorrectOidc() {
	ctx, err := twirp.WithHTTPRequestHeaders(s.ctx, http.Header{"Authorization": []string{"bearer InvalidToken"}})
	s.Require().NoError(err)

	clientWithInvalidAuth := internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithInvalidAuth.GetImageDetails(ctx, &internalapi.GetImageDetailsRequest{})
	s.Require().ErrorContains(err, "twirp error unauthenticated")
	s.Require().ErrorContains(err, "failed to validate bearer token")
	s.Require().Nil(resp)
}

func (s *AuthOidcE2ETestSuite) Test_InternalApi_Success() {
	validAuthHttpClient := s.getOidcHttpClient()
	clientWithValidAuth := internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, validAuthHttpClient)

	resp, err := clientWithValidAuth.GetImageDetails(s.ctx, &internalapi.GetImageDetailsRequest{
		Owner:        &sharedapi.Actor{GlobalId: "test"},
		ImageSource:  "Curated",
		ImageId:      7418451152,
		ImageVersion: "latest",
	})
	s.Require().ErrorContains(err, "twirp error not_found: image definition is not found")
	s.Require().Nil(resp)
}

func (s *AuthOidcE2ETestSuite) Test_ImagesApi_FailsWithoutOidc() {
	ctx, err := twirp.WithHTTPRequestHeaders(s.ctx, http.Header{"Authorization": []string{""}})
	s.Require().NoError(err)

	clientWithoutAuth := imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithoutAuth.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated")
	s.Require().ErrorContains(err, "no bearer token provided")
	s.Require().Nil(resp)
}

func (s *AuthOidcE2ETestSuite) Test_ImagesApi_FailsWithIncorrectOidc() {
	ctx, err := twirp.WithHTTPRequestHeaders(s.ctx, http.Header{"Authorization": []string{"bearer InvalidToken"}})
	s.Require().NoError(err)

	clientWithInvalidAuth := imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, &http.Client{})

	resp, err := clientWithInvalidAuth.ListCuratedImageDefinitions(ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().ErrorContains(err, "twirp error unauthenticated")
	s.Require().ErrorContains(err, "failed to validate bearer token")
	s.Require().Nil(resp)
}

func (s *AuthOidcE2ETestSuite) Test_ImagesApi_Success() {
	validAuthHttpClient := s.getOidcHttpClient()
	clientWithValidAuth := imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, validAuthHttpClient)

	resp, err := clientWithValidAuth.ListCuratedImageDefinitions(s.ctx, &imagesapi.ListCuratedImageDefinitionsRequest{
		Owner:           &sharedapi.Actor{GlobalId: "owner"},
		IncludeDisabled: false,
	})
	s.Require().NoError(err)
	s.Require().NotNil(resp)
}
