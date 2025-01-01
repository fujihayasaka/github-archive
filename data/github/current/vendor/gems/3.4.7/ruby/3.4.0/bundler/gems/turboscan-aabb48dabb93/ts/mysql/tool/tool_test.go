package tool_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	v210 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/google/uuid"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

var testRepoID = ts.RepositoryEID(191)

func toolVersion(guid, name, version string) *ts.ToolVersion {
	return &ts.ToolVersion{
		Name:    ts.ToToolName(name),
		Version: version,
		Tool:    sarif.NewTool(guid, ts.ToToolName(name)),
	}
}

func TestSaveStatus(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()
	doc := samples.RequireSARIF(t, "../sarif/testdata/toolExecutionNotifications.sarif")

	a := &ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/done"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	dbtest.RequireCreate(t, db, a)
	ams := analysismessage.NewService(db)

	err := toolService.CreateAnalysisExtractedFiles(ctx, a, doc.Runs[0], ams)
	require.NoError(t, err)

	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFiles{}))

	var status ts.AnalysisExtractedFiles
	require.NoError(t, db.Find(&status).Error)
	require.ElementsMatch(t, []string{"js"}, maps.Keys(status.FilesExtracted))

	require.NoError(t, toolService.DeleteAnalysisExtractedFiles(ctx, 0, a.ID))
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFiles{}))

	require.NoError(t, toolService.DeleteAnalysisExtractedFiles(ctx, a.RepositoryID, a.ID))
	dbtest.RequireCount(t, 0, db.Model(ts.AnalysisExtractedFiles{}))
}

func TestExtractedFileLimits(t *testing.T) {
	db := dbtest.RequireConnection(t)

	ctx := context.Background()
	doc := samples.RequireSARIF(t, "../sarif/testdata/codeql.sarif")

	a := &ts.Analysis{
		RepositoryID:       testRepoID,
		ID:                 ts.AnalysisID(1),
		SourceRepositoryID: testRepoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/done"),
		Tool: &ts.Tool{
			ID:            1519,
			GUID:          "guid",
			CanonicalName: "CodeQL",
		},
		ToolID: 1519,
	}
	dbtest.RequireCreate(t, db, a)
	ams := analysismessage.NewService(db)

	var analysisMessages []*ts.AnalysisMessage

	// Extracted and not extracted files below the limits
	toolService := tool.NewService(db, limits.TestLimitSelector())
	err := toolService.CreateAnalysisExtractedFiles(ctx, a, doc.Runs[0], ams)
	require.NoError(t, err)

	// -> No messages are created
	require.NoError(t, db.Find(&analysisMessages).Error)
	require.Empty(t, analysisMessages)

	// Extracted and not extracted files exceed the limits
	l := limits.LimitsDefault()
	l.ExtractedFilesLimit = 0
	l.NotExtractedFilesLimit = 0
	ls := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{191: l}, false)

	toolService = tool.NewService(db, ls)
	a.ID = ts.AnalysisID(2)
	err = toolService.CreateAnalysisExtractedFiles(ctx, a, doc.Runs[0], ams)
	require.NoError(t, err)

	// -> 2 MessageSarifSoftLimitExtractedFilesStatus are created because both limits are exceeded
	require.NoError(t, db.Find(&analysisMessages).Error)
	require.Len(t, analysisMessages, 2)
	for _, m := range analysisMessages {
		require.Equal(t, ts.MessageSarifSoftLimitExtractedFilesStatus, m.Key)
	}

	// -> FilesExtracted and FilesNotExtracted are set to nil
	var files ts.AnalysisExtractedFiles
	require.NoError(t, db.Find(&files).Error)
	require.Nil(t, files.FilesExtracted)
	require.Nil(t, files.FilesNotExtracted)
}

func TestSaveToolVersions(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()

	// Tool GUID is given, tool with GUID does not exist -> Create new tool with GUID
	newTool := toolVersion("123", "Tool", "")

	require.NoError(t, toolService.FindOrCreate(ctx, []*ts.ToolVersion{newTool}))
	require.NotZero(t, newTool.ID)
	require.NotZero(t, newTool.Tool.ID)
	require.Equal(t, newTool.Tool.GUID, newTool.Tool.GUID)                   // ?????
	require.Equal(t, newTool.Tool.CanonicalName, newTool.Tool.CanonicalName) // ?????

	sameTool := toolVersion("", "Tool", "")

	// Tool GUID is given, tool with GUID exists -> Return tool from the DB
	require.NoError(t, toolService.FindOrCreate(ctx, []*ts.ToolVersion{sameTool}))
	require.Equal(t, newTool.ID, sameTool.ID)
	require.Equal(t, newTool.Tool.ID, sameTool.Tool.ID)
	require.Equal(t, newTool.Tool.GUID, sameTool.Tool.GUID)
	require.Equal(t, newTool.Name, sameTool.Name)

	sameToolByName := toolVersion("", "Tool", "")

	// Tool GUID is missing, name is given, tool with name exists -> fetch existing entry by name
	require.NoError(t, toolService.FindOrCreate(ctx, []*ts.ToolVersion{sameToolByName}))
	require.Equal(t, newTool.ID, sameToolByName.ID)
	require.Equal(t, newTool.Tool.ID, sameToolByName.Tool.ID)

	newTool = toolVersion("", "New Tool", "")
	// Tool GUID is missing, name is given, tool with name does not exist -> create new tool
	require.NoError(t, toolService.FindOrCreate(ctx, []*ts.ToolVersion{newTool}))
	require.NotZero(t, newTool.Tool.GUID)
	require.EqualValues(t, "New Tool", newTool.Name)
	require.EqualValues(t, "New Tool", newTool.Tool.CanonicalName)
	require.True(t, newTool.Tool.IsInternalGUID)

	// Tool GUID is missing, name is given, version is given, version does not match the one in DB -> create new tool version with same Tool
	newToolVersion := toolVersion("", "New Tool", "0.2")
	require.NoError(t, toolService.FindOrCreate(ctx, []*ts.ToolVersion{newToolVersion}))
	require.NotEqual(t, newTool.ID, newToolVersion.ID)
	require.Equal(t, newTool.Tool.ID, newToolVersion.Tool.ID)
	require.Equal(t, "0.2", newToolVersion.Version)
	require.Equal(t, "", newTool.Version)
	require.True(t, newToolVersion.Tool.IsInternalGUID)
}

func TestToolIDs(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()

	codeQL := ts.Tool{
		ID:            1519,
		GUID:          "guid",
		CanonicalName: "CodeQL",
	}
	pyLint := ts.Tool{
		ID:            1520,
		GUID:          "guid2",
		CanonicalName: "PyLint",
	}

	dbtest.RequireCreate(t, db, &codeQL)
	dbtest.RequireCreate(t, db, &pyLint)

	toolIDs, err := toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: []ts.ToolName{"CodeQL", "PyLint"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 2)
	require.Contains(t, toolIDs, codeQL.ID)
	require.Contains(t, toolIDs, pyLint.ID)

	toolIDs, err = toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: []ts.ToolName{"PyLint"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 1)
	require.Equal(t, pyLint.ID, toolIDs[0])

	toolIDs, err = toolService.ToolIDs(ctx, &ts.ToolsFilter{GUIDs: []string{"guid", "guid2"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 2)
	require.Contains(t, toolIDs, codeQL.ID)
	require.Contains(t, toolIDs, pyLint.ID)

	toolIDs, err = toolService.ToolIDs(ctx, &ts.ToolsFilter{GUIDs: []string{"guid2"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 1)
	require.Equal(t, pyLint.ID, toolIDs[0])

	toolIDs, err = toolService.ToolIDs(ctx, &ts.ToolsFilter{CanonicalNames: []ts.ToolName{"PyLint"}, GUIDs: []string{"guid"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 1)
	require.Equal(t, pyLint.ID, toolIDs[0])

	toolIDs, err = toolService.ToolIDs(ctx, &ts.ToolsFilter{GUIDs: []string{"missing"}})
	require.NoError(t, err)
	require.Len(t, toolIDs, 0)

	toolID, err := toolService.CodeQLToolID(ctx)
	require.NoError(t, err)
	require.Equal(t, codeQL.ID, toolID)
}

func TestToolIds(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()

	globalTool := &ts.Tool{
		CanonicalName: "Other",
	}
	dbtest.RequireCreate(t, db, globalTool)

	toolIDs, err := toolService.ToolsIDsWithRenames(ctx, "Other")
	require.NoError(t, err)
	require.Len(t, toolIDs, 1)
	require.ElementsMatch(t, []ts.ToolID{globalTool.ID}, toolIDs)

	toolIDs, err = toolService.ToolsIDsWithRenames(ctx, "Not Found")
	require.NoError(t, err)
	require.Len(t, toolIDs, 0)
}

func TestToolIdsRenamed(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()

	globalTool := &ts.Tool{
		CanonicalName: "CodeQL",
	}
	renamedTool := &ts.Tool{
		CanonicalName: "CodeQL command-line toolchain",
		GUID:          uuid.Must(uuid.NewRandom()).String(),
	}
	dbtest.RequireCreate(t, db, &ts.Tool{
		CanonicalName: "Other",
		GUID:          uuid.Must(uuid.NewRandom()).String(),
	})
	dbtest.RequireCreate(t, db, globalTool)
	dbtest.RequireCreate(t, db, renamedTool)

	toolIDs, err := toolService.ToolsIDsWithRenames(ctx, "CodeQL")
	require.NoError(t, err)
	require.Len(t, toolIDs, 2)
	require.ElementsMatch(t, []ts.ToolID{globalTool.ID, renamedTool.ID}, toolIDs)
}

func TestToolsUsed(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ctx := context.Background()

	globalTool := &ts.Tool{
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, globalTool)

	a1 := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          "aaaa",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a1)
	a2 := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/branch"),
		CommitOid:          "bbbb",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &a2)

	used, err := toolService.ToolsUsed(ctx, testRepoID)
	require.NoError(t, err)
	require.Len(t, used, 1)
}

func TestToolScope(t *testing.T) {
	db := dbtest.RequireConnection(t)
	dbtest.RequireCreate(t, db, ts.ToolFromCanonicalName("Test Tool"))
	dbtest.RequireCreate(t, db, &ts.Tool{
		CanonicalName: "Test Tool",
		GUID:          "123",
	})
	var tools []*ts.Tool

	require.NoError(t, tool.FindScope(db.Model(ts.Tool{}), ts.ToolFromCanonicalName("Test Tool")).Find(&tools).Error)
	require.Len(t, tools, 1)
	require.Equal(t, "184be173-28e0-640e-4732-988a833f4985", tools[0].GUID)

	require.NoError(t, tool.FindScope(db.Model(ts.Tool{}), &ts.Tool{CanonicalName: "Test Tool", GUID: "123"}).Find(&tools).Error)
	require.Len(t, tools, 1)
	require.Equal(t, "123", tools[0].GUID)

	require.NoError(t, tool.FindScope(db.Model(ts.Tool{}), &ts.Tool{CanonicalName: "Test Tool", GUID: "999"}).Find(&tools).Error)
	require.Len(t, tools, 1)
	require.Equal(t, "123", tools[0].GUID)
}

func TestService_CreateAnalysisExtractedFilesMessages(t *testing.T) {
	db := dbtest.RequireConnection(t)
	toolService := tool.NewService(db, limits.TestLimitSelector())
	ams := analysismessage.NewService(db)

	ctx := context.Background()
	globalTool := &ts.Tool{
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, globalTool)

	analysis := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          "aaaa",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &analysis)
	toolsErrors := map[string]*v210.Notification{
		"a-test-file": {
			Message: &v210.Message{
				Text: "test message",
			},
		},
	}

	err := toolService.CreateAnalysisExtractedFilesMessages(ctx, &analysis, toolsErrors, ams)

	require.NoError(t, err)
}

func TestService_CreateAnalysisExtractedFilesMessages_LimitsExceeded(t *testing.T) {
	l := limits.LimitsDefault()
	l.NotExtractedFilesMessagesLimit = 1
	ls := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{191: l}, false)

	db := dbtest.RequireConnection(t)
	ams := analysismessage.NewService(db)

	toolService := tool.NewService(db, ls)

	ctx := context.Background()
	globalTool := &ts.Tool{
		CanonicalName: "CodeQL",
	}
	dbtest.RequireCreate(t, db, globalTool)

	analysis := ts.Analysis{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Tool:               globalTool,
		ToolID:             globalTool.ID,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          "aaaa",
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, &analysis)

	toolsErrors := map[string]*v210.Notification{
		"a-test-file": {
			Message: &v210.Message{
				Text: "test message",
			},
		},
		"another-test-file": {
			Message: &v210.Message{
				Text: "test message for another file",
			},
		},
	}

	err := toolService.CreateAnalysisExtractedFilesMessages(ctx, &analysis, toolsErrors, ams)
	require.NoError(t, err)

	// only 1 message gets saved because limit is set to 1 above
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisExtractedFilesMessages{}))

	var m ts.AnalysisMessage
	require.NoError(t, db.Find(&m).Error)
	dbtest.RequireCount(t, 1, db.Model(ts.AnalysisMessage{}))
	require.Equal(t, "sarif-soft-limit-not-extracted-files-messages", string(m.Key))
}
