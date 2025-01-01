package main

import (
	"fmt"
	"reflect"
	"testing"

	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/spf13/cobra"
	"github.com/stretchr/testify/assert"
)

// there are only a few fields in the config struct that do not have map structure
// tags and should not be checked against the Cobra command flags. These fields
// are constructed from other fields
var expectNoMapStructTag = map[string]bool{
	"MySQLDBConn":       true,
	"MySQLRODBConn":     true,
	"TrustedKeysParsed": true,
}

// Test that new configuration fields added to configStruct are also added
// as command flags. They must be added in both places to work
func TestConfigAndCmdFlagsMatch(t *testing.T) {
	// initialize the cobra command to check for the presence of all the flags
	cobraFunc := func(*cobra.Command, []string) error {
		return nil
	}
	cmd := initServerCommand(cobraFunc)

	// Use the reflect package to compare the mapstructure tag of configStruct
	// fields to cobra command flag names. The field tag and flag name should match
	config := configStruct{}
	configType := reflect.TypeOf(config)
	for i := 0; i < configType.NumField(); i++ {
		field := configType.Field(i)
		mapstructureTag := field.Tag.Get("mapstructure")

		if mapstructureTag == "" {
			_, ok := expectNoMapStructTag[field.Name]
			assert.True(t, ok, "unexepected map tag for "+field.Name)
		} else {
			assert.NotZero(t, mapstructureTag, fmt.Sprintf("field %s should not have an empty mapstructure tag", field.Name))
			flag := cmd.Flag(mapstructureTag)
			assert.NotNil(t, flag, fmt.Sprintf("no flag found matching the mapstructure field tag %s", mapstructureTag))
		}
	}
}

func TestBuildHMACConfig(t *testing.T) {
	cfg := configStruct{
		PkgWriteAuthConfig: "[{\"clientId\": \"uploading-worker\", \"domain\": \"npm\", \"keys\": [\"mysecretkey\"]}]",
		PkgReadAuthConfig:  "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"anothersecretkey\"]}]",
		LegacyAuthConfig:   "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"onemorekey\"]}]",
		DotcomAuthConfig:   "[{\"clientId\": \"dotcom\", \"domain\": \"github\", \"keys\": [\"dotcomkey\"]}]",
	}
	hmacCfg, err := buildHMACConfig(&cfg)
	assert.Nil(t, err)

	expectedWriteCfg := []auth.ClientConfig{{
		ClientID: "uploading-worker",
		Domain:   "npm",
		Keys:     []string{"mysecretkey"},
	}}
	assert.Equal(t, expectedWriteCfg, hmacCfg.PkgWrite)

	expectedReadCfg := []auth.ClientConfig{{
		ClientID: "npm/read",
		Domain:   "npm",
		Keys:     []string{"anothersecretkey"},
	}}
	assert.Equal(t, expectedReadCfg, hmacCfg.PkgRead)

	expectedLegacyCfg := []auth.ClientConfig{{
		ClientID: "npm/read",
		Domain:   "npm",
		Keys:     []string{"onemorekey"},
	}}
	assert.Equal(t, expectedLegacyCfg, hmacCfg.LegacyTMA)

	expectedDotcomCfg := []auth.ClientConfig{{
		ClientID: "dotcom",
		Domain:   "github",
		Keys:     []string{"dotcomkey"},
	}}
	assert.Equal(t, expectedDotcomCfg, hmacCfg.Dotcom)
}

func TestBuildHMACConfig_Empty(t *testing.T) {
	hmacCfg, err := buildHMACConfig(&configStruct{})
	assert.NotNil(t, err)
	assert.Empty(t, hmacCfg)
}

func TestBuildHMACConfig_PartialConfigsPresent(t *testing.T) {
	hmacCfg, err := buildHMACConfig(&configStruct{
		PkgWriteAuthConfig: "[{\"clientId\": \"uploading-worker\", \"domain\": \"npm\", \"keys\": [\"mysecretkey\"]}]",
		PkgReadAuthConfig:  "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"anothersecretkey\"]}]"})
	assert.NotNil(t, err)
	assert.Empty(t, hmacCfg)
}

// Test that buildHMACConfig fails with an error message that includes the
// specific configStruct field that caused the function to fail
func TestBuildHMACConfigFailsWithExpectedMsg(t *testing.T) {
	type testcase struct {
		cfg                   configStruct
		expectedErrMsgContent string
	}

	testcases := []testcase{
		{
			cfg: configStruct{
				LegacyAuthConfig:   "[{invalid json]",
				PkgReadAuthConfig:  "[{\"clientId\": \"uploading-worker\", \"domain\": \"npm\", \"keys\": [\"mysecretkey\"]}]",
				PkgWriteAuthConfig: "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"anothersecretkey\"]}]",
			},
			expectedErrMsgContent: "failed to parse HMAC configs from legacy-auth-config",
		},
		{
			cfg: configStruct{
				LegacyAuthConfig:   "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"onemorekey\"]}]",
				PkgReadAuthConfig:  "[{invalid json]",
				PkgWriteAuthConfig: "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"anothersecretkey\"]}]",
			},
			expectedErrMsgContent: "failed to parse HMAC configs from pkg-read-auth-config",
		},
		{
			cfg: configStruct{
				LegacyAuthConfig:   "[{\"clientId\": \"npm/read\", \"domain\": \"npm\", \"keys\": [\"onemorekey\"]}]",
				PkgReadAuthConfig:  "[{\"clientId\": \"uploading-worker\", \"domain\": \"npm\", \"keys\": [\"mysecretkey\"]}]",
				PkgWriteAuthConfig: "[{invalid json]",
			},
			expectedErrMsgContent: "failed to parse HMAC configs from pkg-write-auth-config",
		},
	}

	for _, tc := range testcases {
		var cfg = tc.cfg

		hmacCfg, err := buildHMACConfig(&cfg)
		assert.Empty(t, hmacCfg)
		assert.ErrorAs(t, err, &ErrAuthConfig{})
		assert.ErrorContains(t, err, tc.expectedErrMsgContent)
	}
}

func TestInitDatabaseConfig(t *testing.T) {
	t.Run("Only primary", func(t *testing.T) {
		var c = configStruct{
			MySQLUser:     "primary-user",
			MySQLPassword: "primary-passwd",
			MySQLHost:     "primary-host",
			MySQLPort:     "1111",
			MySQLDatabase: "foo",
		}

		initDatabaseConfig(&c)
		assert.Equal(t, "primary-user:primary-passwd@tcp(primary-host:1111)/foo?parseTime=true", c.MySQLDBConn)
		assert.Equal(t, "", c.MySQLRODBConn)
	})

	t.Run("Broken replica config", func(t *testing.T) {
		var c = configStruct{
			MySQLUser:       "primary-user",
			MySQLPassword:   "primary-passwd",
			MySQLHost:       "primary-host",
			MySQLPort:       "1111",
			MySQLDatabase:   "foo",
			MySQLROUser:     "replica-user",
			MySQLROPassword: "replica-passwd",
			MySQLROHost:     "replica-host",
			MySQLROPort:     "2222",
		}

		initDatabaseConfig(&c)
		assert.Equal(t, "primary-user:primary-passwd@tcp(primary-host:1111)/foo?parseTime=true", c.MySQLDBConn)
		assert.Equal(t, "", c.MySQLRODBConn)
	})

	t.Run("Both primary and replica", func(t *testing.T) {
		var c = configStruct{
			MySQLUser:       "primary-user",
			MySQLPassword:   "primary-passwd",
			MySQLHost:       "primary-host",
			MySQLPort:       "1111",
			MySQLDatabase:   "foo",
			MySQLROUser:     "replica-user",
			MySQLROPassword: "replica-passwd",
			MySQLROHost:     "replica-host",
			MySQLROPort:     "2222",
			MySQLRODatabase: "bar",
		}

		initDatabaseConfig(&c)
		assert.Equal(t, "primary-user:primary-passwd@tcp(primary-host:1111)/foo?parseTime=true", c.MySQLDBConn)
		assert.Equal(t, "replica-user:replica-passwd@tcp(replica-host:2222)/bar?parseTime=true", c.MySQLRODBConn)
	})
}
