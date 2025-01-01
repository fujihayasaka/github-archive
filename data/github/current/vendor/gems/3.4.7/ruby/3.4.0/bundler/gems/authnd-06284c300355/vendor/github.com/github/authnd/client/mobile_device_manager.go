package client

import (
	"context"
	"time"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// A MobileDeviceManager represents a connection to the Authnd Mobile Device Management service.
// For optimal network performance, use a single MobileDeviceManager for all your application's requests.
// MobileDeviceManager is safe for concurrent use by multiple goroutines.
type MobileDeviceManager interface {
	// RegisterDeviceKey registers a public key for a mobile device that can be used for authentication or recovery requests.
	RegisterDeviceKey(ctx context.Context, req *pb.RegisterDeviceKeyRequest) (*pb.RegisterDeviceKeyResponse, error)

	// RevokeDeviceKey revokes a public key for a mobile device so that it can no longer be used.
	RevokeDeviceKey(ctx context.Context, req *pb.RevokeDeviceKeyRequest) (*pb.RevokeDeviceKeyResponse, error)

	// RevokeDeviceKeys revokes all mobile device keys for a given user so they can no longer be used.
	RevokeDeviceKeys(ctx context.Context, req *pb.RevokeDeviceKeysRequest) (*pb.RevokeDeviceKeysResponse, error)

	// FindDeviceKeyRegistrations returns all devices associated with a user.
	FindDeviceKeyRegistrations(context.Context, *pb.FindDeviceKeyRegistrationsRequest) (*pb.FindDeviceKeyRegistrationsResponse, error)

	// FindDeviceKeyRegistration retrieves a device key registration associated with a user device.
	FindDeviceKeyRegistration(context.Context, *pb.FindDeviceKeyRegistrationRequest) (*pb.FindDeviceKeyRegistrationResponse, error)

	// RequestDeviceAuth begins the process of authenticating using a user device.
	RequestDeviceAuth(context.Context, *pb.RequestDeviceAuthRequest) (*pb.RequestDeviceAuthResponse, error)

	// GetDeviceAuthStatus retrieves the status of a device auth request.
	GetDeviceAuthStatus(context.Context, *pb.GetDeviceAuthStatusRequest) (*pb.GetDeviceAuthStatusResponse, error)

	// FindActiveDeviceAuth finds an active device auth request for a given user.
	FindActiveDeviceAuth(context.Context, *pb.FindActiveDeviceAuthRequest) (*pb.FindActiveDeviceAuthResponse, error)

	// CompleteDeviceAuth approves or rejects an active device auth request.
	CompleteDeviceAuth(context.Context, *pb.CompleteDeviceAuthRequest) (*pb.CompleteDeviceAuthResponse, error)
}

type mobileDeviceManager struct {
	twirpClient pb.MobileDeviceManager
	statter     stats.Client
}

// NewMobileDeviceManager creates and returns a MobileDeviceManager with the provided options, or an error if applying any of the options failed.
// If no options are provided, recommended options will be applied.
// For optimal network performance, use a single NewMobileDeviceManager for all your application's requests.
// NewMobileDeviceManagers are safe for concurrent use by multiple goroutines.
func NewMobileDeviceManager(addr string, catalogService string, opts ...Option) (MobileDeviceManager, error) {
	if addr == "" {
		return nil, errors.New("must provide a non empty addr")
	}
	if catalogService == "" {
		return nil, errors.New("must provide a non empty catalogService")
	}

	clientOpts := defaultClientOptions()

	// Explicitly disabling retries for mobile device manager.
	opts = append(opts, WithoutRetries())

	err := applyOptions(clientOpts, opts...)
	if err != nil {
		return nil, errors.Wrap(err, "error applying options")
	}

	statter := clientOpts.Statter.WithTags(stats.Tags{
		catalogServiceDimensionName: catalogService,
		clientVersionDimensionName:  Version,
		serviceDimensionName:        "MobileDeviceManager",
	})

	httpClient := clientOpts.CustomHTTPClient
	if httpClient == nil {
		httpClient = createHTTPClient(clientOpts.HTTPClientOptions, statter)
	}

	// always set the catalog service header and user agent
	httpClient = middleware.ApplyCatalogService(httpClient, catalogService)
	httpClient = middleware.ApplyUserAgent(httpClient, Version)

	return &mobileDeviceManager{
		pb.NewMobileDeviceManagerProtobufClient(addr, httpClient),
		statter,
	}, nil
}

// RegisterDeviceKey registers a public key for a mobile device that can be used for authentication or recovery requests.
func (mdm *mobileDeviceManager) RegisterDeviceKey(ctx context.Context, req *pb.RegisterDeviceKeyRequest) (*pb.RegisterDeviceKeyResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "RegisterDeviceKey"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.RegisterDeviceKey(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// RevokeDeviceKey revokes a public key for a mobile device so that it can no longer be used.
func (mdm *mobileDeviceManager) RevokeDeviceKey(ctx context.Context, req *pb.RevokeDeviceKeyRequest) (*pb.RevokeDeviceKeyResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "RevokeDeviceKey"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.RevokeDeviceKey(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// RevokeDeviceKeys revokes all mobile device keys for a given user so they can no longer be used.
func (mdm *mobileDeviceManager) RevokeDeviceKeys(ctx context.Context, req *pb.RevokeDeviceKeysRequest) (*pb.RevokeDeviceKeysResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "RevokeDeviceKeys"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.RevokeDeviceKeys(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// FindDeviceKeyRegistrations returns all devices associated with a user.
func (mdm *mobileDeviceManager) FindDeviceKeyRegistrations(ctx context.Context, req *pb.FindDeviceKeyRegistrationsRequest) (*pb.FindDeviceKeyRegistrationsResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "FindDeviceKeyRegistrations"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.FindDeviceKeyRegistrations(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// FindDeviceKeyRegistration retrieves a device key registration associated with a user device.
func (mdm *mobileDeviceManager) FindDeviceKeyRegistration(ctx context.Context, req *pb.FindDeviceKeyRegistrationRequest) (*pb.FindDeviceKeyRegistrationResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "FindDeviceKeyRegistration"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.FindDeviceKeyRegistration(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// RequestDeviceAuth begins the process of authenticating using a user device.
func (mdm *mobileDeviceManager) RequestDeviceAuth(ctx context.Context, req *pb.RequestDeviceAuthRequest) (*pb.RequestDeviceAuthResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "RequestDeviceAuth"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.RequestDeviceAuth(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// GetDeviceAuthStatus retrieves the status of a device auth request.
func (mdm *mobileDeviceManager) GetDeviceAuthStatus(ctx context.Context, req *pb.GetDeviceAuthStatusRequest) (*pb.GetDeviceAuthStatusResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "GetDeviceAuthStatus"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.GetDeviceAuthStatus(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// FindActiveDeviceAuth finds an active device auth request for a given user.
func (mdm *mobileDeviceManager) FindActiveDeviceAuth(ctx context.Context, req *pb.FindActiveDeviceAuthRequest) (*pb.FindActiveDeviceAuthResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "FindActiveDeviceAuth"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.FindActiveDeviceAuth(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

// CompleteDeviceAuth approves or rejects an active device auth request.
func (mdm *mobileDeviceManager) CompleteDeviceAuth(ctx context.Context, req *pb.CompleteDeviceAuthRequest) (*pb.CompleteDeviceAuthResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "CompleteDeviceAuth"}
	defer func() {
		duration := time.Since(start)
		mdm.statter.Counter(requestsMetric, tags, 1)
		mdm.statter.DistributionMs(timingMetric, tags, duration)
	}()

	response, err := mdm.twirpClient.CompleteDeviceAuth(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}
