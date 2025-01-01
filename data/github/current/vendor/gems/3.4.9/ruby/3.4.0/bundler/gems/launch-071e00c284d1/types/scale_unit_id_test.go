package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewRandomScaleUnitID(t *testing.T) {
	executionID := NewRandomScaleUnitID()
	assert.NotEqual(t, NilScaleUnitID, executionID)
}

// NilScaleUnitID should return nil, nil
func TestScaleUnitIDValueNil(t *testing.T) {
	f := NilScaleUnitID
	val, err := f.Value()
	assert.Nil(t, val)
	assert.Nil(t, err)
}

// A valid ScaleUnitID should return a non-nil value and no error
func TestScaleUnitIDValue(t *testing.T) {
	f := NewRandomScaleUnitID()
	val, err := f.Value()
	assert.NotNil(t, val)
	assert.Nil(t, err)
}
