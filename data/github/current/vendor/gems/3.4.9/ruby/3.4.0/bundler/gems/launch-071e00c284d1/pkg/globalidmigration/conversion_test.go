package globalidmigration

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/observability"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

type mocks struct {
	ghTwirp *ghtwirp.MockClient
}

type conversionSuite struct {
	suite.Suite
	obs        *observability.Observability
	ctx        context.Context
	testLogger testutils.RecordingLogger
	m          mocks
}

func TestProcessor(t *testing.T) {
	suite.Run(t, new(conversionSuite))
}

func (s *conversionSuite) SetupTest() {
	s.ctx = context.Background()
	s.obs = observability.NewNullObservability()

	s.m.ghTwirp = ghtwirp.NewMockClient(s.T())
}

func (s *conversionSuite) Test_ConvertLegacyID() {
	tests := []struct {
		desc          string
		id            string
		field         string
		expectedId    string
		expectedError bool
		setupMock     func(m mocks)
	}{
		{"legacy_id_converted_to_next", "MDM6Qm90NDE4OTgyODI=", "node_id", "BOT_kgDOAn9RKg", false, func(m mocks) {
			s.m.ghTwirp.
				EXPECT().GetNextGlobalID(mock.Anything, "MDM6Qm90NDE4OTgyODI=").
				Return(types.GlobalID("BOT_kgDOAn9RKg"), nil).
				Once()
		}},
		{"next_id_no_conversion", "BOT_kgDOAn9RKg", "node_id", "BOT_kgDOAn9RKg", false, func(m mocks) {}},
		{"invalid_id_with_underscore_no_conversion", "invalid_value", "node_id", "invalid_value", false, func(m mocks) {}},
		{"invalid_id_without_underscore_no_conversion", "invalidValue", "node_id", "invalidValue", false, func(m mocks) {}},
	}
	for _, test := range tests {
		s.Run(test.desc, func() {
			s.SetupTest()
			if test.setupMock != nil {
				test.setupMock(s.m)
			}
			resultId, err := convertLegacyID(s.ctx, s.obs, s.m.ghTwirp, "Test_ConvertLegacyID", test.field, test.id)
			s.Assert().Equal(resultId, test.expectedId)
			if test.expectedError {
				s.Assert().Error(err)
			} else {
				s.Assert().NoError(err)
			}
		})
	}
}

func (s *conversionSuite) Test_ConvertPayloadIDs() {
	s.Run("push.json", func() {
		webhookBytes := fixture(s.T(), "push.json")
		expectedBytes := fixture(s.T(), "converted/push.json")

		s.m.ghTwirp.
			EXPECT().GetNextGlobalID(mock.Anything, "MDQ6VXNlcjQzNTQ4MTk1").
			Return(types.GlobalID("U_kgDOAph-Iw"), nil).
			Times(1)
		s.m.ghTwirp.
			EXPECT().GetNextGlobalID(mock.Anything, "MDEwOlJlcG9zaXRvcnkyMDI5OTc1MDk=").
			Return(types.GlobalID("R_kgDODBl_BQ"), nil).
			Times(1)
		s.m.ghTwirp.
			EXPECT().GetNextGlobalID(mock.Anything, "MDEyOk9yZ2FuaXphdGlvbjQ0MDM2NTYy").
			Return(types.GlobalID("O_kgDOAp_x0g"), nil).
			Times(2)
		s.m.ghTwirp.
			EXPECT().GetNextGlobalID(mock.Anything, "MDIzOkludGVncmF0aW9uSW5zdGFsbGF0aW9uMTcyMDEwMg==").
			Return(types.GlobalID(""), errors.New("twirp error not_found: Next global id does not exist")).
			Maybe()

		resultBytes, err := ConvertPayloadIDs(s.ctx, s.obs, s.m.ghTwirp, "Test_ConvertPayloadIDs", webhookBytes)
		s.Assert().NoError(err)

		resultJSON := string(resultBytes)

		s.Assert().NotContains(resultJSON, "MDQ6VXNlcjQzNTQ4MTk1")
		s.Assert().Contains(resultJSON, "U_kgDOAph-Iw")

		s.Assert().NotContains(resultJSON, "MDEwOlJlcG9zaXRvcnkyMDI5OTc1MDk=")
		s.Assert().Contains(resultJSON, "R_kgDODBl_BQ")

		s.Assert().NotContains(resultJSON, "MDEyOk9yZ2FuaXphdGlvbjQ0MDM2NTYy")
		s.Assert().Contains(resultJSON, "O_kgDOAp_x0g")

		s.Assert().NotContains(resultJSON, `"MDE`)
		s.Assert().NotContains(resultJSON, `"MDQ`)

		// Some entity types return nil for next_global_id which causes a twirp error
		// Make sure we don't call GetNextGlobalID for those types or replace their values
		s.m.ghTwirp.AssertNotCalled(s.T(), "GetNextGlobalID", mock.Anything,
			"MDIzOkludGVncmF0aW9uSW5zdGFsbGF0aW9uMTcyMDEwMg==") // IntegrationInstallation
		s.Assert().Contains(resultJSON,
			"MDIzOkludGVncmF0aW9uSW5zdGFsbGF0aW9uMTcyMDEwMg==") // IntegrationInstallation

		// Make sure we didn't change any unexpected fields
		var resultMap map[string]any
		err = json.Unmarshal(resultBytes, &resultMap)
		s.Assert().NoError(err)

		var expectedMap map[string]any
		err = json.Unmarshal(expectedBytes, &expectedMap)
		s.Assert().NoError(err)

		s.Assert().Equal(resultMap, expectedMap)
	})
}

func fixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}
