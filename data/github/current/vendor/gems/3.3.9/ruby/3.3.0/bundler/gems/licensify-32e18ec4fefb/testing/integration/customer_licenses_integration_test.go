//go:build integration
// +build integration

package integration

import (
	"context"
	"strconv"
	"testing"

	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	protobuf "google.golang.org/protobuf/proto"
)

func TestUpsertAndGetCustomerLicense(t *testing.T) {
	client := NewTestClient(t)

	customerLicenseClient, _, _, _ := client.StartTwirpServer()

	customerLicenseProto := stubs.NewCustomerLicenseProto()

	// Upsert the customer license
	upsertReq := &proto.UpsertCustomerLicenseRequest{CustomerLicense: customerLicenseProto}
	_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), upsertReq)

	require.NoError(t, err)

	// Get the customer license
	getReq := &proto.GetCustomerLicensesRequest{CustomerId: customerLicenseProto.CustomerId, Product: proto.Product_PRODUCT_SDLC}
	resp, err := customerLicenseClient.GetCustomerLicenses(context.Background(), getReq)

	require.NoError(t, err)

	assert.Len(t, resp.CustomerLicenses, 1)
	assert.True(t, protobuf.Equal(customerLicenseProto, resp.CustomerLicenses[0]))
}

func TestGetLicenseeGlobalIds(t *testing.T) {
	client := NewTestClient(t)

	customerLicenseClient, _, _, _ := client.StartTwirpServer()

	protos := []*proto.CustomerLicense{
		stubs.NewCustomerLicenseProto(),
		stubs.NewCustomerLicenseProto(),
	}
	for _, p := range protos {
		upsertReq := &proto.UpsertCustomerLicenseRequest{CustomerLicense: p}
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), upsertReq)
		require.NoError(t, err)
	}

	getReq := &proto.GetLicenseeGlobalIdsRequest{Product: proto.Product_PRODUCT_SDLC, CustomerId: protos[0].CustomerId}
	resp, err := customerLicenseClient.GetLicenseeGlobalIds(context.Background(), getReq)

	require.NoError(t, err)
	assert.Equal(t, []string{protos[0].Licensee.GlobalId}, resp.GlobalIds)
}

func TestGetLicenseesByProductAndEnablementReasons(t *testing.T) {
	client := NewTestClient(t)
	customerLicenseClient, _, _, _ := client.StartTwirpServer()

	customerID := stubs.NewRandomID()

	userID1 := uint64(1)
	license1 := models.NewCustomerLicenseForUserWithMemberships(customerID, userID1, []uint64{100}, nil)

	userID2 := uint64(2)
	license2 := models.NewCustomerLicenseForUserWithMemberships(customerID, userID2, nil, []uint64{200})

	userID3 := uint64(3)
	license3 := models.NewCustomerLicenseForUserWithMemberships(customerID, userID3, []uint64{300}, []uint64{400})

	licenses := []*models.CustomerLicense{license1, license2, license3}
	for _, l := range licenses {
		upsertReq := &proto.UpsertCustomerLicenseRequest{CustomerLicense: l.ToProto()}
		_, err := customerLicenseClient.UpsertCustomerLicense(context.Background(), upsertReq)
		require.NoError(t, err)
	}

	tests := []struct {
		name            string
		request         *proto.GetLicenseeIdsRequest
		wantLicenseeIDs []uint64
	}{
		{
			name: "no reasons",
			request: &proto.GetLicenseeIdsRequest{
				CustomerId: customerID,
				Product:    proto.Product_PRODUCT_SDLC,
			},
			wantLicenseeIDs: []uint64{userID1, userID2, userID3},
		},
		{
			name: "single reason",
			request: &proto.GetLicenseeIdsRequest{
				CustomerId:        customerID,
				Product:           proto.Product_PRODUCT_SDLC,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP},
			},
			wantLicenseeIDs: []uint64{userID1, userID3},
		},
		{
			name: "multiple reasons",
			request: &proto.GetLicenseeIdsRequest{
				CustomerId:        customerID,
				Product:           proto.Product_PRODUCT_SDLC,
				EnablementReasons: []proto.EnablementReason{proto.EnablementReason_ENABLEMENT_REASON_ORG_MEMBERSHIP, proto.EnablementReason_ENABLEMENT_REASON_REPOSITORY_COLLABORATOR},
			},
			wantLicenseeIDs: []uint64{userID1, userID2, userID3},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := customerLicenseClient.GetLicenseeIds(context.Background(), tt.request)
			require.NoError(t, err)

			assert.ElementsMatch(t, tt.wantLicenseeIDs, resp.LicenseeIdsDeprecated)

			// check them as strings too
			wantLicenseeIDsString := make([]string, 0, len(tt.wantLicenseeIDs))
			for _, id := range tt.wantLicenseeIDs {
				wantLicenseeIDsString = append(wantLicenseeIDsString, strconv.FormatUint(id, 10))
			}
			assert.ElementsMatch(t, wantLicenseeIDsString, resp.LicenseeIds)
		})
	}
}
