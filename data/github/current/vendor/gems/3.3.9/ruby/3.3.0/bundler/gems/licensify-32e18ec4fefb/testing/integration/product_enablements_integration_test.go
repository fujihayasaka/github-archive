//go:build integration
// +build integration

package integration

import (
	"context"
	"testing"

	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	protobuf "google.golang.org/protobuf/proto"
)

func TestUpsertAndGetProductEnablement(t *testing.T) {
	client := NewTestClient(t)

	_, productEnablementClient, _, _ := client.StartTwirpServer()

	peProto := stubs.NewProductEnablementProto()

	upsertReq := &proto.UpsertProductEnablementRequest{ProductEnablement: peProto}
	_, err := productEnablementClient.UpsertProductEnablement(context.Background(), upsertReq)

	require.NoError(t, err)

	getReq := &proto.GetProductEnablementsRequest{CustomerId: peProto.CustomerId}
	resp, err := productEnablementClient.GetProductEnablements(context.Background(), getReq)

	require.NoError(t, err)

	assert.Len(t, resp.ProductEnablements, 1)
	assert.True(t, protobuf.Equal(peProto, resp.ProductEnablements[0]))
}
