package spokes

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/assert"
)

type MockObjectsAPI struct {
	ReadObjectsFunc func(context.Context, *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error)
}

func (m *MockObjectsAPI) ReadObjects(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
	return m.ReadObjectsFunc(ctx, req)
}

func (m *MockObjectsAPI) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	return nil, errors.New("not implemented")
}

func (m *MockObjectsAPI) ResolveObjects(ctx context.Context, req *objects.ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return nil, errors.New("not implemented")
}

func (m *MockObjectsAPI) ExpandOids(ctx context.Context, req *objects.ExpandOidsRequest) (*objects.ExpandOidsResponse, error) {
	return nil, errors.New("not implemented")
}

func TestOIDsExist(t *testing.T) {
	tests := []struct {
		name       string
		repoID     uint64
		oids       []string
		mockResp   *objects.ReadObjectsResponse
		mockErr    error
		wantExists map[string]bool
		wantErr    bool
	}{
		{
			name:   "Multiple objects exist",
			repoID: 12345,
			oids:   []string{"abc123", "def456"},
			mockResp: &objects.ReadObjectsResponse{
				Objects: []*objects.Object{
					{Object: &types.Object{Oid: &types.ObjectID{Id: "abc123"}}},
					{Object: &types.Object{Oid: &types.ObjectID{Id: "def456"}}},
				},
			},
			mockErr:    nil,
			wantExists: map[string]bool{"abc123": true, "def456": true},
			wantErr:    false,
		},
		{
			name:   "Some objects exist, some don't",
			repoID: 12345,
			oids:   []string{"abc123", "xyz789"},
			mockResp: &objects.ReadObjectsResponse{
				Objects: []*objects.Object{
					{Object: &types.Object{Oid: &types.ObjectID{Id: "abc123"}}},
				},
			},
			mockErr:    nil,
			wantExists: map[string]bool{"abc123": true, "xyz789": false},
			wantErr:    false,
		},
		{
			name:   "No objects exist",
			repoID: 12345,
			oids:   []string{"notfound1", "notfound2"},
			mockResp: &objects.ReadObjectsResponse{
				Objects: []*objects.Object{},
			},
			mockErr:    nil,
			wantExists: map[string]bool{"notfound1": false, "notfound2": false},
			wantErr:    false,
		},
		{
			name:       "API returns error",
			repoID:     12345,
			oids:       []string{"abc123"},
			mockResp:   nil,
			mockErr:    errors.New("unexpected API failure"),
			wantExists: nil,
			wantErr:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockAPI := &MockObjectsAPI{
				ReadObjectsFunc: func(ctx context.Context, req *objects.ReadObjectsRequest) (*objects.ReadObjectsResponse, error) {
					return tt.mockResp, tt.mockErr
				},
			}

			client := &spokesClient{
				spokesURL:     "http://mock-spokes-url",
				objectsClient: mockAPI,
			}

			existsMap, err := client.OIDsExist(context.Background(), tt.repoID, tt.oids)
			if (err != nil) != tt.wantErr {
				t.Fatalf("got error %v, want error %v", err, tt.wantErr)
			}
			assert.Equalf(t, tt.wantExists, existsMap, "got %v, want %v", existsMap, tt.wantExists)
		})
	}
}

// MockRoundTripper captures how many times RoundTrip is called
type MockRoundTripper struct {
	CallCount int
}

// Custom RoundTrip to satify RoundTripper interface
func (m *MockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	m.CallCount++
	recorder := httptest.NewRecorder()
	recorder.WriteHeader(http.StatusOK)
	return recorder.Result(), nil
}

// TestWithHeaders_NoInfiniteLoop ensures the custom RoundTripper does not cause an infinite loop
func TestWithHeaders_NoInfiniteLoop(t *testing.T) {
	tests := []struct {
		name          string
		expectedCalls int
		wantErr       bool
	}{
		{
			name:          "Request goes through once",
			expectedCalls: 1,
			wantErr:       false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockTransport := &MockRoundTripper{}
			client := &http.Client{Transport: mockTransport}
			client = withHeaders(client, "test-hmac")

			req, _ := http.NewRequest(http.MethodGet, "http://example.com", http.NoBody)

			_, err := client.Do(req)

			if (err != nil) != tt.wantErr {
				t.Fatalf("got error %v, want error %v", err, tt.wantErr)
			}

			if mockTransport.CallCount != tt.expectedCalls {
				t.Fatalf("expected transport to be called %d times, got %d", tt.expectedCalls, mockTransport.CallCount)
			}
		})
	}
}
