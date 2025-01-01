package twirp

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/github/turboscan/ts/mysql/analysismessage"
	"golang.org/x/exp/maps"

	"github.com/aws/smithy-go/ptr"
	"github.com/github/turboscan/ts/gormext"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"
)

func TestSerializeAnalysisKey(t *testing.T) {
	res := serializeAnalysisKey(nil)
	require.Nil(t, res)

	res = serializeAnalysisKey(&ts.Analysis{})
	require.Nil(t, res)

	res = serializeAnalysisKey(&ts.Analysis{ID: 10})
	require.Equal(t, &proto.AnalysisKey{Id: 10, Environment: "{}"}, res)
}

func TestSerializePathWithNullByte(t *testing.T) {
	loc := serializeLocation("\x00", ts.Region{})
	require.NotContains(t, loc.FilePath, "\x00")
}

func TestSerializeAnalysisWithProcessWarnings(t *testing.T) {

	a := ts.Analysis{
		ID:          1,
		Ref:         []byte("myRef"),
		Tool:        &ts.Tool{ID: 123, CanonicalName: "CodeQL"},
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0"},
		CommitOid:   "abcd",
	}

	res := serializeAnalysis(a, nil, false)
	require.EqualValues(t, "", res.ProcessWarning)

	a.AddWarning("test")
	res = serializeAnalysis(a, nil, false)
	require.EqualValues(t, "test", res.ProcessWarning)

	a.AddWarning("foo bar")
	res = serializeAnalysis(a, nil, false)
	require.EqualValues(t, "test\nfoo bar", res.ProcessWarning)
}

func TestSerializeSearchDocumentForInsights(t *testing.T) {
	fixed := false
	enabled := true
	deleted := false

	doc := ts.SearchDocument{
		RepositoryID:        "1",
		OwnerID:             "42",
		AlertID:             1,
		Number:              101,
		CanonicalID:         "1",
		FullDescription:     "XSS is good",
		SarifIdentifier:     "js/good-xss",
		FixedOnDefault:      &fixed,
		Resolution:          "AlertResolutionNone",
		CodeScanningEnabled: &enabled,
		Deleted:             &deleted,
		CreatedAt:           gormext.ConvertTime(ptr.Time(time.Now())),
		UpdatedAt:           gormext.ConvertTime(ptr.Time(time.Now().Add(24 * time.Hour))),
	}

	updatedAlert, createdAlert, err := serializeSearchDocumentForInsights(doc)
	require.NoError(t, err)
	require.EqualValues(t, 1, updatedAlert.Id)
	require.EqualValues(t, 1, createdAlert.Id)
	require.EqualValues(t, 101, updatedAlert.Number)
	require.EqualValues(t, 101, createdAlert.Number)
}

func TestSerializeAnalysisMessages(t *testing.T) {
	tool := ts.Tool{ID: 123, CanonicalName: "CodeQL"}

	a := &ts.LatestAnalysis{
		Analysis: ts.Analysis{
			ID:          1,
			Ref:         []byte("myRef"),
			Tool:        &tool,
			ToolID:      tool.ID,
			ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0", Tool: &tool},
			CommitOid:   "abcd",
			Category:    "test",
		},
		MinCreatedAt: gormext.ConvertTime(ptr.Time(time.Now())),
	}

	db := dbtest.RequireConnection(t)

	as := analysismessage.NewService(db)
	ctx := context.Background()

	res := serializeCategoryStatus(a)

	require.Equal(t, 0, len(res.Messages))

	exitCode := 1
	exitCodeDescription := "Your setup is just borked I'm afraid"

	msg, err := as.SarifExecutionUnsuccessful(ctx, &a.Analysis, exitCode, exitCodeDescription)

	require.NoError(t, err)

	a.AnalysisMessages = append(a.AnalysisMessages, msg)
	res = serializeCategoryStatus(a)

	require.Equal(t, 1, len(res.Messages))

	require.EqualValues(t, ts.MessageSarifExecutionUnsuccessful, res.Messages[0].Key)
	require.Equal(t, proto.AnalysisMessageLevel_DANGER, res.Messages[0].Level)
	require.Equal(t, "CodeQL exited with errors", res.Messages[0].Title)

	expectedMessage := fmt.Sprintf("CodeQL reported the error code 1.\n\nDescription of the error code: %s\n\n[Learn more about CodeQL exit codes.](https://docs.github.com/en/code-security/codeql-cli/codeql-cli-reference/exit-codes)\n[Learn more about troubleshooting the CodeQL workflow.](https://docs.github.com/en/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/troubleshooting-the-codeql-workflow)\n", exitCodeDescription)
	require.EqualValues(t, expectedMessage, res.Messages[0].Message)

	msg.Args = ts.SarifExecutionUnsuccessfulArgs{ExitCode: "1"}

	expectedMessage = "CodeQL reported the error code 1.\n\n[Learn more about CodeQL exit codes.](https://docs.github.com/en/code-security/codeql-cli/codeql-cli-reference/exit-codes)\n[Learn more about troubleshooting the CodeQL workflow.](https://docs.github.com/en/code-security/code-scanning/automatically-scanning-your-code-for-vulnerabilities-and-errors/troubleshooting-the-codeql-workflow)\n"
	v, err := serializeAnalysisMessage(&a.Analysis, msg)
	require.NoError(t, err)
	require.EqualValues(t, expectedMessage, v.Message)

	// The method createAnalysisMessage is consciously not exported to avoid deliberate misuse, however there could be stuff in the DB that for some reason has an unknown AnalysisMessageKey
	// so it's worth testing that we do something in that case.
	a.AnalysisMessages = append(a.AnalysisMessages, &ts.AnalysisMessage{Key: "random-code-with-no-template", Args: nil})

	res = serializeCategoryStatus(a)

	require.EqualValues(t, 2, len(res.Messages))

	defaultError := defaultErrorMessage("Something went wrong with code scanning!")

	require.EqualValues(t, defaultError.Key, res.Messages[1].Key)
	require.EqualValues(t, defaultError.Level, res.Messages[1].Level)

	require.EqualValues(t, "Something went wrong with code scanning!", res.Messages[1].Title)
}

func TestSerializeAnalysisMessagesCodeqlNotification(t *testing.T) {
	tool := ts.Tool{ID: 123, CanonicalName: "CodeQL"}

	a := &ts.LatestAnalysis{
		Analysis: ts.Analysis{
			ID:          1,
			Ref:         []byte("myRef"),
			Tool:        &tool,
			ToolID:      tool.ID,
			ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0", Tool: &tool},
			CommitOid:   "abcd",
			Category:    "test",
		},
		MinCreatedAt: gormext.ConvertTime(ptr.Time(time.Now())),
	}

	var locations []*ts.AnalysisMessageLocation
	locations = append(locations,
		&ts.AnalysisMessageLocation{
			FilePath:    "lib/repository.js",
			StartLine:   12,
			EndLine:     14,
			StartColumn: 2,
			EndColumn:   4,
		},
		&ts.AnalysisMessageLocation{
			FilePath: "lib/repository-full-file.js",
		},
	)

	db := dbtest.RequireConnection(t)
	as := analysismessage.NewService(db)
	ctx := context.Background()

	// none level with markdown message
	msg, err := as.CodeQLNotification(ctx, &a.Analysis, "desc", "id", "", "markdown", "none", []string{"helplink1", "helplink2"}, locations)
	require.NoError(t, err)
	a.AnalysisMessages = append(a.AnalysisMessages, msg)

	// note level with only text message
	msg, err = as.CodeQLNotification(ctx, &a.Analysis, "desc", "id", "text", "", "note", []string{"helplink1", "helplink2"}, locations)
	require.NoError(t, err)
	a.AnalysisMessages = append(a.AnalysisMessages, msg)

	// warning level
	msg, err = as.CodeQLNotification(ctx, &a.Analysis, "desc", "id", "", "markdown", "warning", []string{"helplink1", "helplink2"}, locations)
	require.NoError(t, err)
	a.AnalysisMessages = append(a.AnalysisMessages, msg)

	// error level
	msg, err = as.CodeQLNotification(ctx, &a.Analysis, "desc", "id", "", "markdown", "error", []string{"helplink1", "helplink2"}, locations)
	require.NoError(t, err)
	a.AnalysisMessages = append(a.AnalysisMessages, msg)

	res := serializeCategoryStatus(a)

	require.Equal(t, "codeql/id", res.Messages[0].Key)
	require.Equal(t, "desc", res.Messages[0].Title)

	require.Equal(t, "markdown", res.Messages[0].Message)
	require.Equal(t, "text", res.Messages[1].Message)

	require.Equal(t, proto.AnalysisMessageLevel_SUCCESS, res.Messages[0].Level)
	require.Equal(t, proto.AnalysisMessageLevel_SUCCESS, res.Messages[1].Level)
	require.Equal(t, proto.AnalysisMessageLevel_ATTENTION, res.Messages[2].Level)
	require.Equal(t, proto.AnalysisMessageLevel_DANGER, res.Messages[3].Level)

	require.Equal(t, "lib/repository.js", res.Messages[0].Locations[0].FilePath)
	require.Equal(t, 12, int(res.Messages[0].Locations[0].StartLine))
	require.Equal(t, 14, int(res.Messages[0].Locations[0].EndLine))
	require.Equal(t, 2, int(res.Messages[0].Locations[0].StartColumn))
	require.Equal(t, 4, int(res.Messages[0].Locations[0].EndColumn))
	// The location serializer sets the column/line values to the first line of the file if unset
	// (if the problem is with a whole file not a section of it).
	require.Equal(t, "lib/repository-full-file.js", res.Messages[0].Locations[1].FilePath)
	require.Equal(t, 1, int(res.Messages[0].Locations[1].StartLine))
	require.Equal(t, 1, int(res.Messages[0].Locations[1].StartColumn))
	require.Equal(t, 1, int(res.Messages[0].Locations[1].EndLine))
	require.Equal(t, 1, int(res.Messages[0].Locations[1].EndColumn))

	require.Equal(t, "helplink1", res.Messages[0].HelpLinks[0])
	require.Equal(t, "helplink2", res.Messages[0].HelpLinks[1])
}

func TestLoadNilArgs(t *testing.T) {
	db := dbtest.RequireConnection(t)
	dbtest.RequireCreate(t, db, &ts.AnalysisMessage{Key: ts.MessageSarifExecutionUnsuccessful, RawArgs: json.RawMessage("null")})
	var msg ts.AnalysisMessage
	require.NoError(t, db.Find(&msg).Error)
	require.Equal(t, msg.Args.Key(), ts.MessageSarifExecutionUnsuccessful)
	require.IsType(t, ts.SarifExecutionUnsuccessfulArgs{}, msg.Args)
}

var overwrite = flag.Bool("overwrite", false, "Overwrite existing cassettes")

func TestVerifyAnalysisMessageKeys(t *testing.T) {
	// Verify that all the keys have templates, titles and levels
	var keys []string

	// find all the possible values of AnalysisMessageKey declared in ts/analysis_message.go
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, "../analysis_message.go", nil, parser.ParseComments)
	require.NoError(t, err)
	for _, decl := range f.Decls {
		if node, ok := decl.(*ast.GenDecl); ok {
			// look for constants
			if node.Tok == token.CONST {
				for _, spec := range node.Specs {
					if v, ok := spec.(*ast.ValueSpec); ok {
						if i, ok := v.Type.(*ast.Ident); ok {
							// find constants of type AnalysisMessageKey
							if i.Name == "analysisMessageKey" {
								for _, val := range v.Values {
									// each value will be a quoted string
									if l, ok := val.(*ast.BasicLit); ok {
										key, err := strconv.Unquote(l.Value)
										require.NoError(t, err)
										keys = append(keys, key)
									}
								}
							}
						}
					}
				}
			}
		}
	}

	require.NotEmpty(t, keys)

	toolCodeQL := ts.Tool{ID: 123, CanonicalName: "CodeQL"}
	a := &ts.Analysis{
		ID:          1,
		Ref:         []byte("myRef"),
		Tool:        &toolCodeQL,
		ToolID:      toolCodeQL.ID,
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0", Tool: &toolCodeQL},
		CommitOid:   "abcd",
		Category:    "test",
	}

	tool3rdParty := ts.Tool{ID: 456, CanonicalName: "Mona's Scrutiny"}
	a2 := &ts.Analysis{
		ID:          2,
		Ref:         []byte("myRef"),
		Tool:        &tool3rdParty,
		ToolID:      tool3rdParty.ID,
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0", Tool: &tool3rdParty},
		CommitOid:   "abcd",
		Category:    "test",
	}

	for _, key := range keys {
		var argsCases []ts.AnalysisMessageArgs
		test3rdPartyTool := false

		switch key {
		case string(ts.MessageSarifExecutionUnsuccessful):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifExecutionUnsuccessfulArgs{
					ExitCode: "1",
				},
				ts.SarifExecutionUnsuccessfulArgs{
					ExitCode: "0",
				},
				ts.SarifExecutionUnsuccessfulArgs{
					ExitCode:            "1",
					ExitCodeDescription: "This is really BAD",
				},
				ts.SarifExecutionUnsuccessfulArgs{
					ExitCode:            "0",
					ExitCodeDescription: "This is really BAD",
				},
				ts.SarifExecutionUnsuccessfulArgs{
					ExitCodeDescription: "This is really BAD",
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifNoAnalyzableCode):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifNoAnalyzableCodeArgs{},
			}
		case string(ts.MessageSarifProcessingSoftLimitExceeded):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifProcessingSoftLimitExceededArgs{},
			}
		case string(ts.MessageZipInvalidArgs):
			argsCases = []ts.AnalysisMessageArgs{
				ts.ZipInvalidArgs{
					Empty: true,
				},
				ts.ZipInvalidArgs{
					Empty: false,
				},
			}
		case string(ts.MessageZipTooBigArgs):
			argsCases = []ts.AnalysisMessageArgs{
				ts.ZipTooBigArgs{
					Max: "100 MB",
				},
			}
		case string(ts.MessageSarifTooBigArgs):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifTooBigArgs{
					Max: "100 MB",
				},
			}
		case string(ts.MessageSarifSoftLimitResultsPerRun):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitResultsPerRunArgs{
					Total: 10,
					Limit: 5,
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifSoftLimitThreadFlows):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitThreadFlowsArgs{
					AlertCount:            1,
					MaxThreadFlowsCount:   11,
					Limit:                 10,
					ThreadFlowsAboveLimit: 1,
					ExampleRuleSarifIds:   []string{"rule-1"},
				},
				ts.SarifSoftLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   11,
					Limit:                 10,
					ThreadFlowsAboveLimit: 1,
					ExampleRuleSarifIds:   []string{"rule-1"},
				},
				ts.SarifSoftLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   12,
					Limit:                 10,
					ThreadFlowsAboveLimit: 2,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2"},
				},
				ts.SarifSoftLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   13,
					Limit:                 10,
					ThreadFlowsAboveLimit: 3,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifSoftLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   14,
					Limit:                 10,
					ThreadFlowsAboveLimit: 4,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2", "rule-3"},
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifSoftLimitTagsPerRule):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    6,
					Limit:               5,
					RulesAboveLimit:     1,
					ExampleRuleSarifIds: []string{"rule-1"},
				},
				ts.SarifSoftLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    7,
					Limit:               5,
					RulesAboveLimit:     2,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2"},
				},
				ts.SarifSoftLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    8,
					Limit:               5,
					RulesAboveLimit:     3,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifSoftLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    9,
					Limit:               5,
					RulesAboveLimit:     4,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2", "rule-3"},
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifSoftLimitRelatedLocations):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 1,
					MaxRelatedLocationsCount:   11,
					Limit:                      10,
					RelatedLocationsAboveLimit: 1,
					ExampleRuleSarifIds:        []string{"rule-1"},
				},
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   12,
					Limit:                      10,
					RelatedLocationsAboveLimit: 2,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2"},
				},
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   13,
					Limit:                      10,
					RelatedLocationsAboveLimit: 3,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 4,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 10,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifSoftLimitRelatedLocationsPerResultArgs{
					AlertCount:                 2,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 1,
					ExampleRuleSarifIds:        []string{"rule-1"},
				},
			}
		case string(ts.MessageSarifSoftLimitExtractedFilesStatus):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitExtractedFilesStatusArgs{
					ExtractedStatus: false,
				},
			}
		case string(ts.MessageSarifSoftLimitNotExtractedFilesMessages):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifSoftLimitNotExtractedFilesMessagesArgs{
					Limit:        1000,
					MessageCount: 1001,
				},
			}
		case string(ts.MessageSarifHardLimitRelatedLocations):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 1,
					MaxRelatedLocationsCount:   11,
					Limit:                      10,
					RelatedLocationsAboveLimit: 1,
					ExampleRuleSarifIds:        []string{"rule-1"},
				},
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   12,
					Limit:                      10,
					RelatedLocationsAboveLimit: 2,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2"},
				},
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   13,
					Limit:                      10,
					RelatedLocationsAboveLimit: 3,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 4,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 3,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 10,
					ExampleRuleSarifIds:        []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifHardLimitRelatedLocationsPerResultArgs{
					AlertCount:                 2,
					MaxRelatedLocationsCount:   14,
					Limit:                      10,
					RelatedLocationsAboveLimit: 1,
					ExampleRuleSarifIds:        []string{"rule-1"},
				},
			}
		case string(ts.MessageSarifHardLimitRuns):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitRunsArgs{
					RunCount: 33,
					RunLimit: 20,
				},
			}
		case string(ts.MessageSarifHardLimitResultsPerRun):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitResultsPerRunArgs{
					ResultCount: 30000,
					Limit:       25000,
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifHardLimitRulesPerRun):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitRulesPerRunArgs{
					RuleCount: 30000,
					Limit:     25000,
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifHardLimitTagsPerRule):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    100,
					Limit:               50,
					ExampleRuleSarifIds: []string{"rule-1"},
					RulesAboveLimit:     1,
				},
				ts.SarifHardLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    100,
					Limit:               50,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2"},
					RulesAboveLimit:     2,
				},
				ts.SarifHardLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    100,
					Limit:               50,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2", "rule-3"},
					RulesAboveLimit:     3,
				},
				ts.SarifHardLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    100,
					Limit:               50,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2", "rule-3"},
					RulesAboveLimit:     4,
				},
				ts.SarifHardLimitTagsPerRuleArgs{
					MaxRuleTagsCount:    100,
					Limit:               50,
					ExampleRuleSarifIds: []string{"rule-1", "rule-2", "rule-3"},
					RulesAboveLimit:     9,
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifHardLimitThreadFlows):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitThreadFlowsArgs{
					AlertCount:            1,
					MaxThreadFlowsCount:   10001,
					Limit:                 10000,
					ThreadFlowsAboveLimit: 1,
					ExampleRuleSarifIds:   []string{"rule-1"},
				},
				ts.SarifHardLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   10001,
					Limit:                 10000,
					ThreadFlowsAboveLimit: 1,
					ExampleRuleSarifIds:   []string{"rule-1"},
				},
				ts.SarifHardLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   10002,
					Limit:                 10000,
					ThreadFlowsAboveLimit: 2,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2"},
				},
				ts.SarifHardLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   10003,
					Limit:                 10000,
					ThreadFlowsAboveLimit: 3,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2", "rule-3"},
				},
				ts.SarifHardLimitThreadFlowsArgs{
					AlertCount:            3,
					MaxThreadFlowsCount:   10004,
					Limit:                 10000,
					ThreadFlowsAboveLimit: 4,
					ExampleRuleSarifIds:   []string{"rule-1", "rule-2", "rule-3"},
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifHardLimitToolExtensions):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifHardLimitToolExtensionsArgs{
					Limit:          20,
					ExtensionCount: 25,
				},
			}
			test3rdPartyTool = true
		case string(ts.MessageSarifCodeQLNotification):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifCodeQLNotificationArgs{
					Level:           "error",
					Id:              "test-id",
					MessageMarkdown: "This is a test of a CodeQL notification.\n",
				},
			}
		case string(ts.MessageSarifRunsMergeIgnoredUnsuccessful):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifRunsMergeIgnoredUnsuccessfulArgs{
					ToolName: "The Awesome Analyzer",
				},
			}
		case string(ts.MessageSarifParsingFailed):
			argsCases = []ts.AnalysisMessageArgs{
				ts.SarifParsingFailedArgs{
					Error: "I am a parse error message",
				},
			}
		case string(ts.MessageDefaultSetupRejectedUpload):
			argsCases = []ts.AnalysisMessageArgs{
				ts.DefaultSetupRejectedUploadArgs{},
			}
		case string(ts.MessageSarifNoRuns):
			argsCases = []ts.AnalysisMessageArgs{ts.SarifNoRunsArgs{}}
		case string(ts.MessageLogicalAlertsHardLimitExceeded):
			argsCases = []ts.AnalysisMessageArgs{
				ts.LogicalAlertsHardLimitExceededArgs{
					Limit: 1,
				},
			}
		case string(ts.MessageLogicalAlertsSoftLimitExceeded):
			argsCases = []ts.AnalysisMessageArgs{
				ts.LogicalAlertsSoftLimitExceededArgs{
					Limit:     1,
					HardLimit: 2,
				},
			}
		default:
			panic(errors.Errorf("please add a test for %s", key))
		}

		runAnalysisMessageTestCases(t, key, argsCases, a, "")
		if test3rdPartyTool {
			runAnalysisMessageTestCases(t, key, argsCases, a2, "-3rdparty")
		}
	}
}

func runAnalysisMessageTestCases(t *testing.T, key string, argsCases []ts.AnalysisMessageArgs, a *ts.Analysis, testSetName string) {
	t.Helper()

	// Iterate through test cases
	for i, args := range argsCases {
		// If no template is found, this will return the `defaultErrorMessage`
		// if a template is found but no title or level is found, it will panic
		// the exhaustive linter should avoid any panics, as long as the
		// keys stay in the switch statement.
		// defaultErrorMessage should only ever be caused by a deleted key
		// still being in the DB.
		msg, err := serializeAnalysisMessage(a, &ts.AnalysisMessage{Args: args, AnalysisID: &a.ID})
		require.NoError(t, err)
		if key == string(ts.MessageSarifCodeQLNotification) {
			require.Equal(t, "codeql/test-id", msg.Key)
		} else {
			require.Equal(t, fmt.Sprint(key), msg.Key, "Error on test case %d in test set '%s'", i, testSetName)
		}

		// Read the example message files and check that the message is rendered correctly.
		var exampleFile string
		if i == 0 {
			exampleFile = fmt.Sprintf("message-templates/%s%s.example", key, testSetName)
		} else {
			exampleFile = fmt.Sprintf("message-templates/%s%s-%d.example", key, testSetName, i)
		}

		if *overwrite {
			err := os.WriteFile(exampleFile, []byte(msg.Message), 0644)
			require.NoError(t, err, "Could not write example file %s", exampleFile)
		}
		contents, err := os.ReadFile(exampleFile)
		require.NoError(t, err, "Could not read example file %s", exampleFile)
		require.Equal(t, string(contents), msg.Message, "User-facing error messages have changed, please run 'make messages' to update the recordings.")
	}
}

func TestSerializeClassification(t *testing.T) {
	fc1 := ts.FileClassification{"red", "blue"}
	fc2 := ts.FileClassification{"green", "yellow", "green"}
	fc3 := ts.FileClassification{}

	res1 := serializeClassification(fc1)
	require.EqualValues(t, []string{"blue", "red"}, res1)

	res2 := serializeClassification(fc2)
	require.EqualValues(t, []string{"green", "yellow"}, res2)

	res3 := serializeClassification(fc3)
	require.EqualValues(t, []string(nil), res3)
}

func TestSerializeProcessError(t *testing.T) {
	sarifID, _ := ts.NewSarifID("1440221d-8a6b-4f68-aa19-faad35679640")

	// Add an analysis error

	id := ts.AnalysisID(42)
	analysis := ts.Analysis{
		ID:                 id,
		RepositoryID:       55,
		SourceRepositoryID: 55,
	}

	pe := ts.NewUnrecoverableAnalysisError(analysis.RepositoryID, &analysis, "Test analysis error")
	pe.SarifID = sarifID

	// Add a delivery error

	pe2 := ts.NewUnrecoverableDeliveryError(55, sarifID, "Test delivery error")

	// Check serialization

	res := serializeProcessErrors([]*ts.ProcessError{pe, pe2})
	require.EqualValues(t, "Test analysis error", res[0].Message)
	require.EqualValues(t, "Unrecoverable analysis", res[0].ErrorType)
	require.EqualValues(t, "Test delivery error", res[1].Message)
	require.EqualValues(t, "Unrecoverable delivery", res[1].ErrorType)
}

func Test_serializeCategoryStatus(t *testing.T) {
	type args struct {
		analysis *ts.LatestAnalysis
	}
	tests := []struct {
		name string
		args args
		want *proto.CategoryStatus
	}{
		{
			name: "one tool - no files",
			args: args{
				analysis: &ts.LatestAnalysis{Analysis: getNoFilesAnalysis()},
			},
			want: &proto.CategoryStatus{
				CommitOid:      "abcd",
				ToolVersion:    "1.0",
				AnalysisStatus: proto.AnalysisStatus_PENDING,
			},
		},
		{
			name: "one tool - one file",
			args: args{
				analysis: &ts.LatestAnalysis{Analysis: getOneFileAnalysis()},
			},
			want: &proto.CategoryStatus{
				CommitOid:      "abcd",
				ToolVersion:    "1.0",
				AnalysisStatus: proto.AnalysisStatus_PENDING,
			},
		},
		{
			name: "one tool with limit hit - one file",
			args: args{
				analysis: &ts.LatestAnalysis{Analysis: getOneFileAnalysisWithLimits(t)},
			},
			want: &proto.CategoryStatus{
				CommitOid:      "abcd",
				ToolVersion:    "1.0",
				AnalysisStatus: proto.AnalysisStatus_PENDING,
				Messages: []*proto.AnalysisMessage{
					{
						Title:   "SARIF document exceeded our internal limits",
						Message: "Code scanning results were only partially processed. Some information was discarded due to internal limits:\n\n * Rules: Processed 1000, discarded 30\n * Tags: Processed 10, discarded 30\n * Something: Processed 100, discarded 30\n\n\nFor more information about limits and capacity, please read our [documentation](https://docs.github.com/en/rest/code-scanning#upload-an-analysis-as-sarif-data).\n",
						Level:   proto.AnalysisMessageLevel_ATTENTION,
						Key:     string(ts.MessageSarifProcessingSoftLimitExceeded),
					},
				},
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := serializeCategoryStatus(tt.args.analysis)
			require.Equal(t, tt.want.CommitOid, got.CommitOid)
			require.Equal(t, tt.want.ToolVersion, got.ToolVersion)
			require.Equal(t, tt.want.AnalysisStatus, got.AnalysisStatus)
			for j, m := range got.Messages {
				require.Equal(t, tt.want.Messages[j].Key, m.Key)
				require.Equal(t, tt.want.Messages[j].Level, m.Level)
				require.Equal(t, tt.want.Messages[j].Message, m.Message)
				require.Equal(t, tt.want.Messages[j].Title, m.Title)
			}
		})
	}
}

func getNoFilesAnalysis() ts.Analysis {
	analysisNoFiles := ts.Analysis{
		ID:          1,
		Ref:         []byte("myRef"),
		Tool:        &ts.Tool{ID: 123, CanonicalName: "CodeQL"},
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0"},
		CommitOid:   "abcd",
	}

	toolStatusNoFiles := &ts.AnalysisExtractedFiles{
		ID:                1,
		AnalysisID:        1,
		RepositoryID:      1,
		FilesExtracted:    make(ts.ToolStatusFiles),
		FilesNotExtracted: make(ts.ToolStatusFiles),
		Analysis:          &analysisNoFiles,
	}

	analysisNoFiles.AnalysisExtractedFiles = toolStatusNoFiles
	return analysisNoFiles
}

func getOneFileAnalysis() ts.Analysis {
	analysisOneFile := ts.Analysis{
		ID:          1,
		Ref:         []byte("myRef"),
		Tool:        &ts.Tool{ID: 123, CanonicalName: "CodeQL"},
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0"},
		ToolID:      1,
		CommitOid:   "abcd",
	}

	toolStatusOneFile := &ts.AnalysisExtractedFiles{
		ID:                1,
		AnalysisID:        1,
		RepositoryID:      1,
		FilesExtracted:    make(ts.ToolStatusFiles),
		FilesNotExtracted: make(ts.ToolStatusFiles),
		Analysis:          &analysisOneFile,
	}

	toolStatusOneFile.FilesExtracted["javascript"] = map[string]struct{}{"file1.js": {}}
	toolStatusOneFile.FilesNotExtracted["javascript"] = map[string]struct{}{}
	analysisOneFile.AnalysisExtractedFiles = toolStatusOneFile
	return analysisOneFile
}

func TestFiles(t *testing.T) {
	a := ts.AnalysisExtractedFiles{}
	require.NoError(t, json.Unmarshal([]byte(`{"cpp": ["a.cpp", "b.cpp"]}`), &a.FilesExtracted))
	require.NoError(t, json.Unmarshal([]byte(`{"cpp": ["d.cpp", "e.cpp"]}`), &a.FilesNotExtracted))

	b := ts.AnalysisExtractedFiles{}
	require.NoError(t, json.Unmarshal([]byte(`null`), &b.FilesExtracted))
	require.NoError(t, json.Unmarshal([]byte(`null`), &b.FilesNotExtracted))

	total, languages := getToolStatusExtractedMap([]*ts.AnalysisExtractedFiles{&a, &b})

	require.Equal(t, uint64(4), total.Total)
	require.Equal(t, uint64(2), total.Extracted)
	require.Contains(t, languages, "C/C++")
	require.Equal(t, uint64(4), languages["C/C++"].Total)
	require.Equal(t, uint64(2), languages["C/C++"].Extracted)
}

func TestSerializeExtractedFiles(t *testing.T) {
	s := []*ts.AnalysisExtractedFiles{
		{
			FilesExtracted:    ts.ToolStatusFiles(nil),
			FilesNotExtracted: ts.ToolStatusFiles(nil),
		},
		{
			FilesExtracted:    nil,
			FilesNotExtracted: nil,
		},
		{
			FilesExtracted:    map[string]ts.FileSet{"java": {}},
			FilesNotExtracted: map[string]ts.FileSet{"java": {}},
		},
		{
			FilesExtracted:    map[string]ts.FileSet{},
			FilesNotExtracted: map[string]ts.FileSet{},
		},
		{
			FilesExtracted:    map[string]ts.FileSet{"java": {"a.java": {}}},
			FilesNotExtracted: map[string]ts.FileSet{"java": {"b.java": {}}},
		},
		{
			FilesExtracted:    map[string]ts.FileSet{"java": {"b.java": {}}},
			FilesNotExtracted: map[string]ts.FileSet{"java": {"a.java": {}}},
		},
	}
	total, languages := getToolStatusExtractedMap(s)
	require.Equal(t, uint64(2), total.Total)
	require.Equal(t, uint64(2), total.Extracted)
	require.Contains(t, languages, "Java/Kotlin")
	require.Equal(t, uint64(2), languages["Java/Kotlin"].Total)
	require.Equal(t, uint64(2), languages["Java/Kotlin"].Extracted)
}

func TestSerializeExtractedCategoryFiles(t *testing.T) {
	toolErrors := map[string]string{
		"b.java": "Error: Unterminated string constant",
	}
	analysisID := ts.AnalysisID(1)
	analyses := []*ts.Analysis{
		{
			ID:          analysisID,
			Ref:         []byte("myRef"),
			Tool:        &ts.Tool{ID: 123, CanonicalName: "CodeQL"},
			ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0"},
			ToolID:      1,
			CommitOid:   "abcd",
			Category:    "category-a",
			AnalysisMessages: []*ts.AnalysisMessage{
				{
					AnalysisID:   &analysisID,
					RepositoryID: 1,
					Key:          ts.MessageSarifProcessingSoftLimitExceeded,
					RawArgs: json.RawMessage(`{"Limits": [{"name": "Rules", "dropped": 30, "max": 1000},
												{"name": "Tags", "dropped": 30, "max": 10},
												{"name": "Something", "dropped": 30, "max": 100}]}`),
				},
			},
			AnalysisExtractedFiles: &ts.AnalysisExtractedFiles{
				FilesExtracted:    map[string]ts.FileSet{"java": {"a.java": {}}},
				FilesNotExtracted: map[string]ts.FileSet{"java": {"b.java": {}}},
			},
		},
	}

	categories := serializeExtractedCategoryFiles(analyses, toolErrors)
	require.Equal(t, 1, len(categories))
	require.Len(t, categories, 1)
	require.Contains(t, categories, "category-a")
	category := categories["category-a"]
	require.Len(t, category.Languages, 1)

	require.Contains(t, category.Languages, "java")
	lang := category.Languages["java"]

	require.Len(t, lang.Files, 2)

	require.True(t, lang.Files[0].Success)
	require.Equal(t, lang.Files[0].Path, []byte("a.java"))

	require.False(t, lang.Files[1].Success)
	require.Equal(t, lang.Files[1].Path, []byte("b.java"))
	require.Equal(t, lang.Files[1].Message, []byte("Error: Unterminated string constant"))
}

func TestSerializeExtractedFilesRenamesQueryIdName(t *testing.T) {
	s := []*ts.AnalysisExtractedFiles{
		{
			FilesExtracted:    map[string]ts.FileSet{"java": {"a.java": {}}},
			FilesNotExtracted: map[string]ts.FileSet{"java": {"b.java": {}}},
		},
	}
	extracted, _ := getExtractedAndNotExtractedToolStatusFiles(s)
	require.ElementsMatch(t, []string{"Java/Kotlin"}, maps.Keys(extracted))
	require.ElementsMatch(t, []string{"a.java"}, maps.Keys(extracted["Java/Kotlin"]))
}

func TestSerializeExtractedFilesPreservesDisplayNames(t *testing.T) {
	s := []*ts.AnalysisExtractedFiles{
		{
			FilesExtracted:    map[string]ts.FileSet{"Java": {"a.java": {}}},
			FilesNotExtracted: map[string]ts.FileSet{"Java": {"b.java": {}}},
		},
	}
	extracted, _ := getExtractedAndNotExtractedToolStatusFiles(s)
	require.ElementsMatch(t, []string{"Java"}, maps.Keys(extracted))
	require.ElementsMatch(t, []string{"a.java"}, maps.Keys(extracted["Java"]))
}

func TestSerializeExtractedFilesWithSublanguagesSometimesEnabled(t *testing.T) {
	s := []*ts.AnalysisExtractedFiles{
		{
			FilesExtracted:    map[string]ts.FileSet{"java": {"a.java": {}, "c.kt": {}}},
			FilesNotExtracted: map[string]ts.FileSet{},
		},
		{
			FilesExtracted:    map[string]ts.FileSet{"Java": {"b.java": {}}, "Kotlin": {"c.kt": {}}},
			FilesNotExtracted: map[string]ts.FileSet{},
		},
	}
	extracted, _ := getExtractedAndNotExtractedToolStatusFiles(s)
	// Gracefully degrade to parent "Java/Kotlin" language
	require.ElementsMatch(t, []string{"Java/Kotlin"}, maps.Keys(extracted))
	require.ElementsMatch(t, []string{"a.java", "b.java", "c.kt"}, maps.Keys(extracted["Java/Kotlin"]))
}

func TestSerializeExtractedFilesWithSublanguagesEnabledInExtracted(t *testing.T) {
	s := []*ts.AnalysisExtractedFiles{
		{
			FilesExtracted:    map[string]ts.FileSet{},
			FilesNotExtracted: map[string]ts.FileSet{"java": {"a.java": {}, "c.kt": {}}},
		},
		{
			FilesExtracted:    map[string]ts.FileSet{"Java": {"b.java": {}}, "Kotlin": {"c.kt": {}}},
			FilesNotExtracted: map[string]ts.FileSet{},
		},
	}
	extracted, notExtracted := getExtractedAndNotExtractedToolStatusFiles(s)
	// Gracefully degrade to parent "Java/Kotlin" language
	require.ElementsMatch(t, []string{"Java/Kotlin"}, maps.Keys(extracted))
	require.ElementsMatch(t, []string{"b.java", "c.kt"}, maps.Keys(extracted["Java/Kotlin"]))
	require.ElementsMatch(t, []string{"Java/Kotlin"}, maps.Keys(notExtracted))
	// It's expected that `notExtracted` contains some files in `extracted` at this stage, because
	// this method naively combines the sets. We handle these duplicates later (`extracted` wins).
	require.ElementsMatch(t, []string{"a.java", "c.kt"}, maps.Keys(notExtracted["Java/Kotlin"]))
}

func getOneFileAnalysisWithLimits(t *testing.T) ts.Analysis {
	t.Helper()

	analysisID := ts.AnalysisID(1)
	analysisOneFile := ts.Analysis{
		ID:          analysisID,
		Ref:         []byte("myRef"),
		Tool:        &ts.Tool{ID: 123, CanonicalName: "CodeQL"},
		ToolVersion: &ts.ToolVersion{ID: 1, Version: "1.0"},
		ToolID:      1,
		CommitOid:   "abcd",
		AnalysisMessages: []*ts.AnalysisMessage{
			{
				AnalysisID:   &analysisID,
				RepositoryID: 1,
				Key:          ts.MessageSarifProcessingSoftLimitExceeded,
				RawArgs: json.RawMessage(`{"Limits": [{"name": "Rules", "dropped": 30, "max": 1000},
											{"name": "Tags", "dropped": 30, "max": 10},
											{"name": "Something", "dropped": 30, "max": 100}]}`),
			},
		},
	}

	for _, msg := range analysisOneFile.AnalysisMessages {
		require.NoError(t, msg.AfterFind(nil))
	}

	toolStatusOneFile := &ts.AnalysisExtractedFiles{
		ID:                1,
		AnalysisID:        1,
		RepositoryID:      1,
		FilesExtracted:    make(ts.ToolStatusFiles),
		FilesNotExtracted: make(ts.ToolStatusFiles),
		Analysis:          &analysisOneFile,
	}

	toolStatusOneFile.FilesExtracted["javascript"] = map[string]struct{}{"file1.js": {}}
	toolStatusOneFile.FilesNotExtracted["javascript"] = map[string]struct{}{}
	analysisOneFile.AnalysisExtractedFiles = toolStatusOneFile
	return analysisOneFile
}
