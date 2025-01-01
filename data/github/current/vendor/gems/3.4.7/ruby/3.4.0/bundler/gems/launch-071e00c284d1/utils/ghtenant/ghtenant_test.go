package ghtenant

import (
	"context"
	"net/http"
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability/logger"
)

var (
	stubTenantID       = int64(1)
	stubTenantSlug     = "slug"
	expectedTenantID   = stubTenantID
	expectedTenantSlug = stubTenantSlug

	stubEmptyContext                 = context.Background()
	stubContextWithTenantID          = context.WithValue(stubEmptyContext, ghtenantIDCtxKey{}, stubTenantID)
	stubContextWithTenantSlug        = context.WithValue(stubEmptyContext, ghtenantSlugCtxKey{}, stubTenantSlug)
	stubContextWithTenantIDAndSlug   = context.WithValue(stubContextWithTenantSlug, ghtenantIDCtxKey{}, stubTenantID)
	stubContextWithMalformedTenantID = context.WithValue(stubContextWithTenantSlug, ghtenantIDCtxKey{}, "not-an-int")
	stubContextWithEmptyTenantSlug   = context.WithValue(stubContextWithTenantID, ghtenantSlugCtxKey{}, "")
)

func Test_GitHubTenantIDFromContext(t *testing.T) {
	test := []struct {
		name           string
		ctx            context.Context
		isMultiTenant  bool
		shouldErr      bool
		expectedTenant GitHubTenant
	}{
		{
			name: "not-multi-tenant",
			ctx:  stubEmptyContext,
		},
		{
			name:          "multi-tenant/tenant-id-and-slug",
			ctx:           stubContextWithTenantIDAndSlug,
			isMultiTenant: true,
			expectedTenant: GitHubTenant{
				ID:   expectedTenantID,
				Slug: expectedTenantSlug,
			},
		},
		{
			name:          "multi-tenant/empty-context",
			ctx:           stubEmptyContext,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/no-tenant-id",
			ctx:           stubContextWithTenantSlug,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/no-tenant-slug",
			ctx:           stubContextWithTenantID,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/invalid-tenant-id",
			ctx:           stubContextWithMalformedTenantID,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/empty-tenant-slug",
			ctx:           stubContextWithEmptyTenantSlug,
			isMultiTenant: true,
			shouldErr:     true,
		},
	}

	for _, tc := range test {
		t.Run(tc.name, func(t *testing.T) {
			r := require.New(t)

			tenant, err := GitHubTenantFromContext(tc.ctx, tc.isMultiTenant)

			if tc.shouldErr {
				r.Error(err)
				return
			}

			r.NoError(err)
			r.Equal(tc.expectedTenant, tenant)
		})
	}
}

func TestGitHubTenant_Validate(t *testing.T) {
	tenantID := int64(1)
	tenantSlug := "slug"

	tests := []struct {
		name          string
		gitHubTenant  GitHubTenant
		isMultiTenant bool
		shouldErr     bool
	}{
		{
			name: "non-multi-tenant/empty-values",
		},
		{
			name: "non-multi-tenant/tenant-id-set",
			gitHubTenant: GitHubTenant{
				ID: tenantID,
			},
			shouldErr: true,
		},
		{
			name: "non-multi-tenant/tenant-slug-set",
			gitHubTenant: GitHubTenant{
				Slug: tenantSlug,
			},
			shouldErr: true,
		},
		{
			name:          "multi-tenant/valid-values",
			isMultiTenant: true,
			gitHubTenant: GitHubTenant{
				ID:   tenantID,
				Slug: tenantSlug,
			},
		},
		{
			name:          "multi-tenant/empty-values",
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name: "multi-tenant/missing-tenant-id",
			gitHubTenant: GitHubTenant{
				Slug: tenantSlug,
			},
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name: "multi-tenant/missing-tenant-slug",
			gitHubTenant: GitHubTenant{
				ID: tenantID,
			},
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name: "multi-tenant/invalid-tenant-id",
			gitHubTenant: GitHubTenant{
				ID:   -1,
				Slug: tenantSlug,
			},
			isMultiTenant: true,
			shouldErr:     true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			r := require.New(t)

			err := test.gitHubTenant.Validate(test.isMultiTenant)

			if test.shouldErr {
				r.Error(err)
				return
			}

			r.NoError(err)
		})
	}
}

func Test_GitHubTenantFromContext(t *testing.T) {
	test := []struct {
		name           string
		ctx            context.Context
		isMultiTenant  bool
		shouldErr      bool
		expectedTenant GitHubTenant
	}{
		{
			name: "not-multi-tenant",
			ctx:  stubEmptyContext,
		},
		{
			name:          "multi-tenant/tenant-id-and-slug",
			ctx:           stubContextWithTenantIDAndSlug,
			isMultiTenant: true,
			expectedTenant: GitHubTenant{
				ID:   expectedTenantID,
				Slug: expectedTenantSlug,
			},
		},
		{
			name:          "multi-tenant/empty-context",
			ctx:           stubEmptyContext,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/no-tenant-id",
			ctx:           stubContextWithTenantSlug,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/no-tenant-slug",
			ctx:           stubContextWithTenantID,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/invalid-tenant-id",
			ctx:           stubContextWithMalformedTenantID,
			isMultiTenant: true,
			shouldErr:     true,
		},
		{
			name:          "multi-tenant/empty-tenant-slug",
			ctx:           stubContextWithEmptyTenantSlug,
			isMultiTenant: true,
			shouldErr:     true,
		},
	}

	for _, tc := range test {
		t.Run(tc.name, func(t *testing.T) {
			r := require.New(t)

			tenant, err := GitHubTenantFromContext(tc.ctx, tc.isMultiTenant)

			if tc.shouldErr {
				r.Error(err)
				return
			}

			r.NoError(err)
			r.Equal(tc.expectedTenant, tenant)
		})
	}
}

func Test_TenantIDFromContext(t *testing.T) {
	tests := map[string]struct {
		ctx              context.Context
		isMultiTenant    bool
		shouldErr        bool
		expectedTenantID int64
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/tenant-not-found": {
			isMultiTenant: true,
			ctx:           context.Background(),
			shouldErr:     true,
		},
		"multi-tenant/invalid-id": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantIDCtxKey{}, "boom"),
			shouldErr:     true,
		},
		"multi-tenant/valid-id": {
			isMultiTenant:    true,
			ctx:              context.WithValue(context.Background(), ghtenantIDCtxKey{}, int64(1)),
			expectedTenantID: int64(1),
		},
	}

	for testName, v := range tests {
		testData := v
		t.Run(testName, func(t *testing.T) {
			r := require.New(t)

			tenantID, err := TenantIDFromContext(testData.ctx, testData.isMultiTenant)

			if testData.shouldErr {
				r.Error(err)
				return
			}

			r.NoError(err)
			r.Equal(testData.expectedTenantID, tenantID)
		})
	}
}

func Test_TenantSlugFromContext(t *testing.T) {
	tests := map[string]struct {
		ctx                context.Context
		isMultiTenant      bool
		shouldErr          bool
		expectedTenantSlug string
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/tenant-not-found": {
			isMultiTenant: true,
			ctx:           context.Background(),
			shouldErr:     true,
		},
		"multi-tenant/valid-slug": {
			isMultiTenant:      true,
			ctx:                context.WithValue(context.Background(), ghtenantSlugCtxKey{}, "staffship-01"),
			expectedTenantSlug: "staffship-01",
		},
		"multi-tenant/malformed-slug": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantSlugCtxKey{}, 1),
			shouldErr:     true,
		},
		"multi-tenant/empty-slug": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantSlugCtxKey{}, ""),
			shouldErr:     true,
		},
	}

	for testName, v := range tests {
		testData := v
		t.Run(testName, func(t *testing.T) {
			r := require.New(t)

			tenantSlug, err := TenantSlugFromContext(testData.ctx, testData.isMultiTenant)

			if testData.shouldErr {
				r.Error(err)
				return
			}

			r.NoError(err)
			r.Equal(testData.expectedTenantSlug, tenantSlug)
		})
	}
}

func Test_ContextWithTenantID(t *testing.T) {
	tests := map[string]struct {
		ctx              context.Context
		tenantID         int64
		isMultiTenant    bool
		shouldHaveTenant bool
		shouldErr        bool
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/id-is-zero": {
			isMultiTenant: true,
			ctx:           context.Background(),
			shouldErr:     true,
		},
		"multi-tenant/id-is-negetive": {
			isMultiTenant: true,
			tenantID:      int64(0),
			ctx:           context.Background(),
			shouldErr:     true,
		},
		"multi-tenant/valid-context": {
			isMultiTenant:    true,
			ctx:              context.Background(),
			shouldHaveTenant: true,
			tenantID:         int64(1),
		},
	}

	for test, v := range tests {
		testData := v

		t.Run(test, func(t *testing.T) {
			r := require.New(t)

			ctx, err := ContextWithTenantID(testData.ctx, testData.tenantID, testData.isMultiTenant)

			if testData.shouldErr {
				r.Error(err)
				return
			}

			if testData.shouldHaveTenant {
				r.NotNil(ctx)
				tenantIDVal := ctx.Value(ghtenantIDCtxKey{})

				r.NotEmptyf(tenantIDVal, "expected tenant id in context, but wasn't found")

				tenantID, ok := tenantIDVal.(int64)
				r.Truef(ok, "expected tenant id %+v to be int64")
				r.Equal(tenantID, testData.tenantID)
			}
		})
	}
}

func Test_ContextWithTenantSlug(t *testing.T) {
	tests := map[string]struct {
		ctx              context.Context
		tenantSlug       string
		isMultiTenant    bool
		shouldHaveTenant bool
		shouldErr        bool
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/slug-is-empty": {
			isMultiTenant: true,
			tenantSlug:    "",
			ctx:           context.Background(),
			shouldErr:     true,
		},
		"multi-tenant/valid-context": {
			isMultiTenant:    true,
			ctx:              context.Background(),
			shouldHaveTenant: true,
			tenantSlug:       "staffship-01",
		},
	}

	for test, v := range tests {
		testData := v

		t.Run(test, func(t *testing.T) {
			r := require.New(t)

			ctx, err := ContextWithTenantSlug(testData.ctx, testData.tenantSlug, testData.isMultiTenant)

			if testData.shouldErr {
				r.Error(err)
				return
			}

			if testData.shouldHaveTenant {
				r.NotNil(ctx)
				tenantSlugVal := ctx.Value(ghtenantSlugCtxKey{})

				r.NotEmptyf(tenantSlugVal, "expected tenant slug in context, but wasn't found")
				r.Equal(tenantSlugVal, testData.tenantSlug)
			}
		})
	}
}

func Test_ForwardGitHubTenant(t *testing.T) {
	tests := map[string]struct {
		ctx             context.Context
		isMultiTenant   bool
		shouldErr       bool
		expectedHeaders map[string]string
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/invalid-tenant-id": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantIDCtxKey{}, "boom"),
			shouldErr:     true,
		},
		"multi-tenant/valid-tenant-id-and-slug": {
			isMultiTenant: true,
			ctx: context.WithValue(
				context.WithValue(context.Background(), ghtenantIDCtxKey{}, int64(1)),
				ghtenantSlugCtxKey{},
				"staffship-01",
			),
			expectedHeaders: map[string]string{
				"X-GitHub-Tenant-ID": "1",
				"X-GitHub-Tenant":    "staffship-01",
			},
		},
		"multi-tenant/missing-tenant-slug": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantIDCtxKey{}, int64(1)),
			expectedHeaders: map[string]string{
				"X-GitHub-Tenant-ID": "1",
				"X-GitHub-Tenant":    "id=1",
			},
		},
	}

	for test, v := range tests {
		testData := v

		t.Run(test, func(t *testing.T) {
			r := require.New(t)

			req := &http.Request{
				Header: http.Header{},
			}
			req = req.WithContext(testData.ctx)
			err := ForwardGitHubTenant(req, testData.isMultiTenant, logger.TestLogger())
			header := req.Header

			if testData.shouldErr {
				r.Error(err)
				r.Empty(header)
				return
			}

			r.NoError(err)
			if testData.expectedHeaders != nil {
				r.Equal(len(testData.expectedHeaders), len(header))
				for k, v := range testData.expectedHeaders {
					r.Equal(v, header.Get(k))
				}
			}
		})
	}
}

func Test_SetTwirpTenantHeader(t *testing.T) {
	tests := map[string]struct {
		ctx             context.Context
		isMultiTenant   bool
		shouldErr       bool
		existingHeaders map[string]string
		expectedHeaders map[string]string
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/invalid-tenant-id": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantIDCtxKey{}, "boom"),
			shouldErr:     true,
		},
		"multi-tenant/valid-tenant-id-and-slug": {
			isMultiTenant: true,
			ctx: context.WithValue(
				context.WithValue(context.Background(), ghtenantIDCtxKey{}, int64(1)),
				ghtenantSlugCtxKey{},
				"staffship-01",
			),
			expectedHeaders: map[string]string{
				"X-GitHub-Tenant-ID": "1",
				"X-GitHub-Tenant":    "staffship-01",
			},
		},
		"multi-tenant/existing-header": {
			isMultiTenant: true,
			ctx:           context.WithValue(context.Background(), ghtenantIDCtxKey{}, int64(1)),
			existingHeaders: map[string]string{
				"blah": "foo",
			},
			expectedHeaders: map[string]string{
				"X-GitHub-Tenant-ID": "1",
				"X-GitHub-Tenant":    "id=1",
				"blah":               "foo",
			},
		},
	}

	for test, v := range tests {
		testData := v

		t.Run(test, func(t *testing.T) {
			r := require.New(t)

			if testData.existingHeaders != nil {
				hdrs := make(http.Header)
				for k, v := range testData.existingHeaders {
					hdrs.Set(k, v)
				}
				testData.ctx, _ = twirp.WithHTTPRequestHeaders(testData.ctx, hdrs)
			}

			ctx, err := ContextWithTwirpTenantHeaders(testData.ctx, testData.isMultiTenant, logger.TestLogger())

			if testData.shouldErr {
				r.Error(err)
				return
			}

			r.NotNil(ctx)
			header, ok := twirp.HTTPRequestHeaders(ctx)

			if !testData.isMultiTenant {
				r.False(ok)
				r.NoError(err)
				return
			}

			r.True(ok)
			if testData.expectedHeaders != nil {
				r.Equal(len(testData.expectedHeaders), len(header))
				for k, v := range testData.expectedHeaders {
					r.Equal(v, header.Get(k))
				}
			}
		})
	}
}

func TestValidateTenantSlug(t *testing.T) {
	tests := []struct {
		name    string
		slug    interface{}
		want    string
		wantErr bool
	}{
		{
			name:    "valid slug",
			slug:    "my-tenant",
			want:    "my-tenant",
			wantErr: false,
		},
		{
			name:    "empty slug",
			slug:    "",
			want:    "",
			wantErr: true,
		},
		{
			name:    "invalid slug type",
			slug:    123,
			want:    "",
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ValidateTenantSlug(tt.slug)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateTenantSlug() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("ValidateTenantSlug() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestValidateTenantID(t *testing.T) {
	tests := []struct {
		name     string
		tenantID interface{}
		want     int64
		wantErr  bool
	}{
		{
			name:     "valid int64 tenant ID",
			tenantID: int64(123),
			want:     123,
			wantErr:  false,
		},
		{
			name:     "valid string tenant ID",
			tenantID: "123",
			want:     123,
			wantErr:  false,
		},
		{
			name:     "invalid tenant ID type",
			tenantID: true,
			want:     0,
			wantErr:  true,
		},
		{
			name:     "invalid non-integer string tenant ID",
			tenantID: "not-a-number",
			want:     0,
			wantErr:  true,
		},
		{
			name:     "zero string tenant ID",
			tenantID: "0",
			want:     0,
			wantErr:  true,
		},
		{
			name:     "zero tenant ID",
			tenantID: int64(0),
			want:     0,
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ValidateTenantID(tt.tenantID)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateTenantID() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("ValidateTenantID() = %v, want %v", got, tt.want)
			}
		})
	}
}

func Test_ContextWithSerializeLoginHeader(t *testing.T) {
	tests := map[string]struct {
		ctx               context.Context
		serializerMode    string
		isMultiTenant     bool
		shouldErr         bool
		shouldHeaderExist bool
		expectedHeader    http.Header
	}{
		"not-multi-tenant": {
			ctx: context.Background(),
		},
		"multi-tenant/valid-serialize-mode": {
			ctx:               context.Background(),
			serializerMode:    SerializeLoginDisplay,
			isMultiTenant:     true,
			shouldHeaderExist: true,
			expectedHeader: http.Header{
				SerializeLoginHeader: []string{SerializeLoginDisplay},
			},
		},
		"multi-tenant/invalid-serialize-mode": {
			ctx:            context.Background(),
			serializerMode: "invalid",
			isMultiTenant:  true,
			shouldErr:      true,
		},
	}

	for test, v := range tests {

		t.Run(test, func(t *testing.T) {
			r := require.New(t)

			ctx, err := ContextWithSerializeLoginHeader(v.ctx, v.serializerMode, v.isMultiTenant)
			if v.shouldErr {
				r.Error(err)
				return
			}

			header, ok := twirp.HTTPRequestHeaders(ctx)
			if !ok && v.shouldHeaderExist {
				t.Error("expected header to exist")
			}

			r.Equal(v.expectedHeader, header)
		})
	}
}
