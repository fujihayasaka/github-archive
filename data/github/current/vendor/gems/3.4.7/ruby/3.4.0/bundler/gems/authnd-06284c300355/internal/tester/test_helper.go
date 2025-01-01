package tester

import (
	"context"

	"github.com/github/authnd/client"
	pb "github.com/github/authnd/client/proto/authentication/v0"
)

type mockAuthndClient struct {
	authFunc   func(req *client.AuthenticateRequest) (*client.AuthenticateResponse, error)
	issueFunc  func(req *pb.IssueTokenRequest) (*pb.IssueTokenResponse, error)
	ssatFunc   func(req *pb.IssueSignedAuthTokenRequest) (*pb.IssueSignedAuthTokenResponse, error)
	verifyFunc func(req *pb.VerifyRequest) (*pb.BatchVerifyResponse, error)
	revokeFunc func(req *pb.RevokeRequest) (*pb.BatchRevokeResponse, error)
	findFunc   func(req *pb.FindCredentialsRequest) (*pb.FindCredentialsResponse, error)
}

func (m *mockAuthndClient) Authenticate(ctx context.Context, request *client.AuthenticateRequest, opts ...client.RequestOption) (*client.AuthenticateResponse, error) {
	return m.authFunc(request)
}

func (m *mockAuthndClient) IssueSignedAuthToken(ctx context.Context, request *pb.IssueSignedAuthTokenRequest, opts ...client.RequestOption) (*pb.IssueSignedAuthTokenResponse, error) {
	return m.ssatFunc(request)
}

func (m *mockAuthndClient) IssueToken(ctx context.Context, request *pb.IssueTokenRequest, opts ...client.RequestOption) (*pb.IssueTokenResponse, error) {
	return m.issueFunc(request)
}

func (m *mockAuthndClient) VerifyCredentials(ctx context.Context, request *pb.VerifyRequest, opts ...client.RequestOption) (*pb.BatchVerifyResponse, error) {
	return m.verifyFunc(request)
}

func (m *mockAuthndClient) RevokeCredentials(ctx context.Context, request *pb.RevokeRequest, opts ...client.RequestOption) (*pb.BatchRevokeResponse, error) {
	return m.revokeFunc(request)
}

func (m *mockAuthndClient) FindCredentials(ctx context.Context, request *pb.FindCredentialsRequest, opts ...client.RequestOption) (*pb.FindCredentialsResponse, error) {
	return m.findFunc(request)
}

type mockTokenExchanger struct {
	exchangeFunc func(ctx context.Context, request *client.ExchangeTokenRequest, opts ...client.RequestOption) (*client.ExchangeTokenResponse, error)
}

func (m *mockTokenExchanger) ExchangeToken(ctx context.Context, request *client.ExchangeTokenRequest, opts ...client.RequestOption) (*client.ExchangeTokenResponse, error) {
	return m.exchangeFunc(ctx, request, opts...)
}

type mockExchangeTokenVerifier struct {
	verifyFunc func(token string) ([]*pb.Attribute, error)
}

func (m *mockExchangeTokenVerifier) VerifyToken(token string) ([]*pb.Attribute, error) {
	return m.verifyFunc(token)
}
