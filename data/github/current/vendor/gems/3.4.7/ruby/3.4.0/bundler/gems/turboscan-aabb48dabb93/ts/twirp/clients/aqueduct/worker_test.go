package aqueduct_test

import (
	"context"
	"fmt"
	"sort"
	"testing"

	"github.com/github/turboscan/ts/appctx"

	"encoding/json"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/mock"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

func TestEnabledQueues_All(t *testing.T) {
	r := baseRegistry()
	allQs := sort.StringSlice(maps.Keys(r))
	enabledQs := aqueduct.EnabledQueues("", r, log.NewNullLogger())
	enabledQsNames := sort.StringSlice(maps.Keys(enabledQs))

	require.Equal(t, allQs, enabledQsNames)
}

func TestEnabledQueues_None(t *testing.T) {
	r := baseRegistry()
	enabledQs := aqueduct.EnabledQueues("potato", r, log.NewNullLogger())

	require.Len(t, enabledQs, 0)
}

func TestEnabledQueues_OnlyOne(t *testing.T) {
	logger := log.NewNullLogger()

	r := baseRegistry()
	aqueduct.RegisterJob[aqueduct.TestJob](r)

	enabledQs := aqueduct.EnabledQueues(aqueduct.TestJob{}.Queue(), r, logger)
	require.Len(t, enabledQs, 1)

	// Test with trailing comma
	enabledQs = aqueduct.EnabledQueues(fmt.Sprintf("%s,", aqueduct.TestJob{}.Queue()), r, logger)
	require.Len(t, enabledQs, 1)
}

func baseRegistry() aqueduct.Registry {
	r := aqueduct.Registry{}
	aqueduct.RegisterJob[aqueduct.EchoJob](r)
	return r
}

// requireMockReporter returns a Reporter and predicate that we can use for testing.
// The exceptions package provides some support for writing a mock, but the Reporter
// is only defined as a struct (and not interface) so we need some extra steps.
// The first return item is the Reporter we can use in the App.
// The second return item is a predicate that (once called) will
// say whether we did call the Reporter.
func requireMockReporter(t *testing.T) (*exceptions.Reporter, func() bool) {
	t.Helper()
	exporter := mock.NewExporter(
		// noop
		func(ctx context.Context, data []byte) error {
			return nil
		},
	)

	r, err := exceptions.NewReporter(
		exceptions.WithApplication("my-app"), // Required by the exceptions pkg
		exceptions.WithExporter(exporter),
	)
	require.NoError(t, err)

	return r, func() bool {
		// The `inInvoked` method is on the exporter, not the reporter,
		// se we need to return it explicitly.
		return exporter.IsInvoked()
	}

}

func TestBaseHandlerPerform_Retries(t *testing.T) {
	r := baseRegistry()
	aqueduct.RegisterJob[aqueduct.TestErrorJob](r)
	queue := aqueduct.TestErrorJob{}.Queue()
	reporter, reporterInvoked := requireMockReporter(t)
	ctx := appctx.WithReporter(context.Background(), reporter)

	handler, ok := r[queue]
	assert.True(t, ok)

	aqueductMock := &aqueduct.AqueductMock{}

	rr := &aq.ReceiveResult{Job: aq.Job{
		ID:      "42",
		Payload: []byte(`{"queue":"turboscan-test-error"}`),
	}}

	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	err := handler(context.Background(), nil, aqueductMock, *rr)
	assert.EqualError(t, err, "empty err")
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	require.Equal(t, aqueduct.TestErrorJob{}, aqueductMock.EnqueuedJobs()[0])

	err = handler(context.Background(), nil, aqueductMock, *rr)
	assert.EqualError(t, err, "empty err")
	require.Len(t, aqueductMock.EnqueuedJobs(), 2)
	require.Equal(t, aqueduct.TestErrorJob{}, aqueductMock.EnqueuedJobs()[1])

	// over max retries
	rr = &aq.ReceiveResult{Job: aq.Job{
		ID:      "43",
		Payload: []byte(`{"queue":"turboscan-test-error"}`),
		Headers: map[string]string{
			aqueduct.RetryCountHeader: "10",
		},
	}}
	aqueductMock.Reset()
	err = handler(ctx, nil, aqueductMock, *rr)
	assert.EqualError(t, err, "empty err")
	require.Len(t, aqueductMock.EnqueuedJobs(), 0)
	require.True(t, reporterInvoked())
}

type testTenantJob struct{}

func (j testTenantJob) Name() string {
	return "testTenantJob"
}

func (j testTenantJob) Queue() string {
	return "turboscan-test-error"
}

func (j testTenantJob) Perform(ctx context.Context, tss *aqueduct.TSServices) error {

	slug := tenant.GetTenant(ctx)
	id := tenant.GetTenantID(ctx)
	if slug == "avocado" && id == "12345" {
		return nil
	}
	return errors.New("no tenant data")
}

func (j testTenantJob) GetRepositoryID() *ts.RepositoryEID {
	return nil
}

func (j testTenantJob) GetRetryBackoffFunc() aqueduct.RetryBackoffFunc {
	return aqueduct.DefaultRetryBackoffFunc
}

func TestBaseHandler_Tenant(t *testing.T) {
	r := baseRegistry()

	j := testTenantJob{}

	aqueduct.RegisterJob[testTenantJob](r)
	queue := testTenantJob{}.Queue()

	handler, ok := r[queue]
	assert.True(t, ok)

	p, err := json.Marshal(j)
	if err != nil {
		return
	}

	job := aq.Job{
		App:     "my app",
		Queue:   j.Queue(),
		Payload: p,
		Headers: map[string]string{headers.Tenant: "avocado", headers.TenantID: "12345"},
	}

	rr := &aq.ReceiveResult{Job: job}

	aqueductMock := &aqueduct.AqueductMock{}

	// handler called perform_later method on testTenantJob
	err = handler(context.Background(), nil, aqueductMock, *rr)
	require.NoError(t, err)
}
