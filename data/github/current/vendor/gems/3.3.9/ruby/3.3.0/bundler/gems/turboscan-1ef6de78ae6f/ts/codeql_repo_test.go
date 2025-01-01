package ts_test

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestCodeqlRepoWriteAndRead(t *testing.T) {
	db := dbtest.RequireConnection(t)

	codeqlRepo := &ts.CodeqlRepo{
		RepositoryID:        1,
		SupportedLanguages:  []string{"python", "ruby"},
		QuerySuite:          ts.QuerySuite_EXTENDED,
		ThreatModel:         ts.ThreatModel_REMOTE,
		EnabledByActorLogin: "actor",
	}

	dbtest.RequireCreate(t, db, codeqlRepo)

	var out ts.CodeqlRepo
	err := db.First(&out).Error
	require.NoError(t, err)
}

func TestDebuggableConfig(t *testing.T) {
	// return current config
	currentConfig := &ts.CodeqlConfig{}

	codeqlRepo := ts.CodeqlRepo{
		CurrentConfig: currentConfig,
	}
	debuggableConfig := codeqlRepo.DebuggableConfig()
	require.Equal(t, currentConfig, debuggableConfig)

	// returns failed config
	failedConfig := &ts.CodeqlConfig{}

	codeqlRepo = ts.CodeqlRepo{
		CurrentConfig: currentConfig,
		FailedConfig:  failedConfig,
	}
	debuggableConfig = codeqlRepo.DebuggableConfig()
	require.Equal(t, failedConfig, debuggableConfig)

	// returns staged config
	stagedConfig := &ts.CodeqlConfig{}

	codeqlRepo = ts.CodeqlRepo{
		CurrentConfig: currentConfig,
		FailedConfig:  failedConfig,
		StagedConfig:  stagedConfig,
	}
	debuggableConfig = codeqlRepo.DebuggableConfig()
	require.Equal(t, stagedConfig, debuggableConfig)
}
