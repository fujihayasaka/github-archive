package e2e

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	adminapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/admin_api"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	internalapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/internal_api"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/stretchr/testify/suite"
)

var (
	uniquePrefixLock  = &sync.Mutex{}
	uniquePrefixBase  = ""
	uniquePrefixId    = 0
	serverAddressLock = &sync.Mutex{}
	serverAddress     = ""
)

type BaseE2ETestSuite struct {
	suite.Suite

	ctx                      context.Context
	serverUrl                string
	customerTwirpClient      imagesapi.ImageManagementService
	adminTwirpClient         adminapi.ImageManagementAdminService
	internalTwirpClient      internalapi.InternalImageManagementService
	uniquePrefix             string
	sourceVhdUrlForQuickFail string
}

func (s *BaseE2ETestSuite) SetupSuite() {
	s.ctx = context.Background()
	s.uniquePrefix = generateUniquePrefixForTestSuite()
	s.sourceVhdUrlForQuickFail = "https://hostedcomputeimsimages.blob.core.windows.net/images/test.vhd"
	s.T().Logf("Unique prefix for test suite: %s", s.uniquePrefix)

	var err error
	s.serverUrl, err = getServerAddress()
	s.Require().NoError(err)

	// Use hmac auth for both images and internal API because e2e tests are run against real environments
	// Generating vssf auth token for real environment is tricky. So, we test Vssf auth separately in AuthOidcE2ETestSuite test suite
	imagesApiHttpClient := s.getHmacHttpClient()

	s.customerTwirpClient = imagesapi.NewImageManagementServiceProtobufClient(s.serverUrl, imagesApiHttpClient)
	s.adminTwirpClient = adminapi.NewImageManagementAdminServiceProtobufClient(s.serverUrl, imagesApiHttpClient)
	s.internalTwirpClient = internalapi.NewInternalImageManagementServiceProtobufClient(s.serverUrl, imagesApiHttpClient)
}

func generateUniquePrefixForTestSuite() string {
	uniquePrefixLock.Lock()
	defer uniquePrefixLock.Unlock()

	if uniquePrefixBase == "" {
		uniquePrefixBase = strings.Replace(time.Now().Format("20060102150405.000"), ".", "", 1)
	}

	uniquePrefixId++

	return fmt.Sprintf("%s%02d", uniquePrefixBase, uniquePrefixId)
}

func getServerAddress() (string, error) {
	// use locks to avoid concurent calling minikube ip
	serverAddressLock.Lock()
	defer serverAddressLock.Unlock()

	if serverAddress == "" {
		serverAddress = os.Getenv("TWIRP_SERVER_URL")
	}

	if serverAddress == "" {
		kubeAddress, err := utils.GetMinikubeIp()
		if err != nil {
			return "", err
		}

		serverAddress = fmt.Sprintf("http://%s:21010", kubeAddress)
	}

	return serverAddress, nil
}
