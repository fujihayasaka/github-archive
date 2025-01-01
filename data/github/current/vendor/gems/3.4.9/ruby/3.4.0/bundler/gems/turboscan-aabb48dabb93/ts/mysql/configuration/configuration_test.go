package configuration_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/stretchr/testify/assert"
)

var testRepoID = ts.RepositoryEID(191)
var testRef = []byte("refs/heads/main")
var testToolID = ts.ToolID(1)
var testCategory = ts.Category("java")

func TestConfiguration(t *testing.T) {
	db := dbtest.RequireConnection(t)
	configurationService := configuration.NewService(db)
	ctx := context.Background()

	initialConfiguration := ts.Configuration{
		RepositoryID: testRepoID,
		Ref:          testRef,
		ToolID:       testToolID,
		Category:     testCategory,
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &initialConfiguration))
	assert.NotEqual(t, ts.ConfigurationID(0), initialConfiguration.ID)

	sameConfiguration := ts.Configuration{
		RepositoryID: testRepoID,
		Ref:          testRef,
		ToolID:       testToolID,
		Category:     testCategory,
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &sameConfiguration))
	assert.Equal(t, initialConfiguration.ID, sameConfiguration.ID)

	differentRepository := ts.Configuration{
		RepositoryID: ts.RepositoryEID(192),
		Ref:          testRef,
		ToolID:       testToolID,
		Category:     testCategory,
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &differentRepository))
	assert.NotEqual(t, ts.ConfigurationID(0), differentRepository.ID)
	assert.NotEqual(t, initialConfiguration.ID, differentRepository.ID)

	differentRef := ts.Configuration{
		RepositoryID: testRepoID,
		Ref:          []byte("refs/heads/branch"),
		ToolID:       testToolID,
		Category:     testCategory,
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &differentRef))
	assert.NotEqual(t, ts.ConfigurationID(0), differentRef.ID)
	assert.NotEqual(t, initialConfiguration.ID, differentRef.ID)

	differentTool := ts.Configuration{
		RepositoryID: testRepoID,
		Ref:          testRef,
		ToolID:       ts.ToolID(2),
		Category:     testCategory,
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &differentTool))
	assert.NotEqual(t, ts.ConfigurationID(0), differentTool.ID)
	assert.NotEqual(t, initialConfiguration.ID, differentTool.ID)

	differentCategory := ts.Configuration{
		RepositoryID: testRepoID,
		Ref:          testRef,
		ToolID:       testToolID,
		Category:     ts.Category("python"),
	}
	assert.NoError(t, configurationService.FindOrCreate(ctx, &differentCategory))
	assert.NotEqual(t, ts.ConfigurationID(0), differentCategory.ID)
	assert.NotEqual(t, initialConfiguration.ID, differentCategory.ID)
}
