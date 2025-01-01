package models

import (
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/github/licensify/testing/stubs"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestProductEnablementToProto(t *testing.T) {
	customerID := uint64(1)
	product := ProductGhas
	globalID := "globalId-1"
	enablementType := ProductEnablementTypeRepo
	enablementID := uint64(100)

	productEnablement := &ProductEnablement{
		Key: &Key{
			PartitionKey: fmt.Sprintf("%d/%s", customerID, "ProductEnablement"),
			ID:           fmt.Sprintf("%s:%d:%s", enablementType, enablementID, product),
		},
		CustomerID:     customerID,
		Product:        product,
		EnablementType: enablementType,
		EnablementID:   enablementID,
		GlobalID:       globalID,
		EnabledAt:      time.Now().Unix(),
	}

	proto := productEnablement.ToProto()

	assert.Equal(t, customerID, proto.CustomerId)
	assert.Equal(t, product.ToProto(), proto.Product)
	assert.Equal(t, enablementType.ToProto(), proto.EnablementType)
	assert.Equal(t, enablementID, proto.EnablementId)
	assert.Equal(t, globalID, proto.GlobalId)
	assert.Equal(t, productEnablement.EnabledAt, proto.EnabledAt.AsTime().Unix())
}

func TestProductEnablementMarshalJSONValidInputs(t *testing.T) {
	customerID := uint64(1)
	enablementID := 1
	globalID := "globalId-1"

	tests := []struct {
		name           string
		product        Product
		enablementType ProductEnablementType
	}{
		{
			name:           "repo target type",
			product:        ProductGhas,
			enablementType: ProductEnablementTypeRepo,
		},
		{
			name:           "org target type",
			product:        ProductGhas,
			enablementType: ProductEnablementTypeOrg,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			model := &ProductEnablement{
				Key: &Key{
					PartitionKey: fmt.Sprintf("%d/%s", customerID, "ProductEnablement"),
					ID:           fmt.Sprintf("%s:%s:%d", tt.product, tt.enablementType, enablementID),
				},
				CustomerID:     customerID,
				Product:        tt.product,
				EnablementType: tt.enablementType,
				GlobalID:       globalID,
				EnabledAt:      1611316800,
			}
			marshaled, err := json.Marshal(model)
			if err != nil {
				t.Errorf("expected err to be nil, got %v", err)
			}

			var unmarshaled ProductEnablement
			err = json.Unmarshal(marshaled, &unmarshaled)

			require.NoError(t, err)
			assert.Equal(t, model, &unmarshaled)
		})
	}
}

func TestProductEnablementUnmarshalJSONWithInvalidInputs(t *testing.T) {
	tests := []struct {
		name           string
		product        string
		enablementType string
		globalID       string
	}{
		{
			name:           "invalid Product",
			product:        "invalid",
			enablementType: ProductEnablementTypeRepo.String(),
			globalID:       "globalId-1",
		},
		{
			name:           "invalid ProductEnablementType",
			product:        ProductGhas.String(),
			enablementType: "invalid",
			globalID:       "globalId-2",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data := []byte(`{"type":"ProductEnablement","id":"` + tt.product + ":" + tt.enablementType + `:100","customerId":1,"product":"` + tt.product + `","enablementType":"` + tt.enablementType + `","globalId":"` + tt.globalID + `","enabledAt":1611316800}`)
			var productEnablement ProductEnablement
			err := json.Unmarshal(data, &productEnablement)

			require.Error(t, err)
			assert.ErrorContains(t, err, tt.name)
		})
	}
}

func TestNewProductEnablementSetsCorrectKey(t *testing.T) {
	proto := stubs.NewProductEnablementProto()
	pe := NewProductEnablementFromProto(proto)

	wantID := fmt.Sprintf("%s:%s:%d", Product(proto.Product), ProductEnablementType(proto.EnablementType), proto.GetEnablementId())
	wantPK := fmt.Sprintf("%d/%s", proto.GetCustomerId(), "ProductEnablement")

	assert.Equal(t, wantID, pe.ID)
	assert.Equal(t, wantPK, pe.PartitionKey)
}
