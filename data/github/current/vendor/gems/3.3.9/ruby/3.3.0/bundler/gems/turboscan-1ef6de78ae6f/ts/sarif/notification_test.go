package sarif_test

import (
	"encoding/json"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/sarif"
	"github.com/github/turboscan/ts/sarif/samples"
	v2_1_0_turboscan "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

func TestGetSuccessfullyExtractedFiles(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	paths, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.Equal(t, 1, len(paths))
}

// TestGetSuccessfullyExtractedFilesInconsistentCodeQL to be deleted once CodeQL 2.11.14 has been rolled out.
func TestGetSuccessfullyExtractedFilesInconsistentCodeQL(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-execution-notification-inconsistent-codeql.sarif")
	paths, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.Equal(t, 1, len(paths))
}

// TestGetSuccessfullyExtractedFilesInconsistentCodeQL2 to be deleted once CodeQL 2.11.14 has been rolled out.
func TestGetSuccessfullyExtractedFilesInconsistentCodeQL2(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-execution-notification-inconsistent-codeql-2.sarif")
	paths, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.Equal(t, 1, len(paths))
}

func TestGetSuccessfullyExtractedFilesExtensionLookup(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotificationExtensionLookup.sarif")
	paths, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.Equal(t, 1, len(paths))
}

func TestToolComponent_NotificationsWithTag(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	require.Equal(t, 1, len(doc.Runs[0].Tool.Driver.NotificationsWithTag(v2_1_0_turboscan.SuccessfullyExtracted)))
	require.Equal(t, 1, len(doc.Runs[0].Tool.Driver.NotificationsWithTag(v2_1_0_turboscan.BaselineExtracted)))
}

func TestFileSet_MarshalAndUnmarshalJSON(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	paths, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	data, err := json.Marshal(paths)
	require.NoError(t, err)
	newPaths := make(map[string]ts.FileSet)
	err = json.Unmarshal(data, &newPaths)
	require.NoError(t, err)
	require.Equal(t, paths, newPaths)
}

func TestGetExtractedFiles(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	success, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, success)

	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, baseline)

	extracted, err := sarif.GetExtractedFiles(doc.Runs[0], baseline)
	require.NoError(t, err)
	require.Equal(t, 1, len(extracted))
	require.Contains(t, extracted, "js")
	require.Equal(t, 1, len(extracted["js"]))
	require.Contains(t, extracted["js"], "lib/repository.js")
}

func TestGetExtractedFilesIgnoresLanguagesWithZeroExtractedFiles(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-with-single-language-extracted.sarif")
	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, baseline)

	extracted, err := sarif.GetExtractedFiles(doc.Runs[0], baseline)
	require.NoError(t, err)
	// Swift is absent since it has zero extracted files.
	require.Equal(t, 1, len(extracted))
	require.Contains(t, extracted, "JavaScript")
	require.Equal(t, 1, len(extracted["JavaScript"]))
	require.Contains(t, extracted["JavaScript"], "lib/repository.js")
}

func TestGetNotExtractedFiles(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	success, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, success)

	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, baseline)

	allSuccess := ts.FileSetUnion(maps.Values(success)...)
	notExtracted := sarif.GetNotExtractedFiles(baseline, allSuccess)
	require.NotEmpty(t, notExtracted)

	require.Equal(t, 1, len(notExtracted))
	require.Contains(t, notExtracted, "js")
	require.Equal(t, 1, len(notExtracted["js"]))
	require.Contains(t, notExtracted["js"], "lib/fingerprints.js")
}

func TestGetNotExtractedFilesIgnoresLanguagesWithZeroExtractedFiles(t *testing.T) {
	baseline := map[string]ts.FileSet{
		"Java":       {"path/to/file.java": struct{}{}},
		"JavaScript": {},
	}
	allSuccess := ts.FileSet{"path/to/file.java": struct{}{}}

	notExtracted := sarif.GetNotExtractedFiles(baseline, allSuccess)
	require.Equal(t, 1, len(notExtracted))
	require.Contains(t, notExtracted, "Java")
	require.Equal(t, 0, len(notExtracted["Java"]))
}

func TestGetNotExtractedFilesAccountsForSublanguages(t *testing.T) {
	// The SARIF file contains Java, Kotlin and Python files.
	// Only Java was extracted.
	// We want GetNotExtractedFiles to return the Java and Kotlin, but not Python.
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-with-single-language-extracted-but-sublanguage.sarif")
	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.Contains(t, baseline, "Java")
	require.Contains(t, baseline, "Kotlin")
	require.Contains(t, baseline, "Python")

	success, err := sarif.GetExtractedFiles(doc.Runs[0], baseline)
	require.NoError(t, err)
	require.Len(t, success, 2)
	require.Contains(t, success, "Java")
	require.Len(t, success["Java"], 1)
	require.Contains(t, success, "Kotlin")
	require.Len(t, success["Kotlin"], 0)

	allSuccess := ts.FileSetUnion(maps.Values(success)...)
	notExtracted := sarif.GetNotExtractedFiles(baseline, allSuccess)
	require.Len(t, notExtracted, 2)
	require.Contains(t, notExtracted, "Java")
	require.Contains(t, notExtracted, "Kotlin")
}

func TestGetNotExtractedFilesMapsSublanguagesCandJS(t *testing.T) {
	baseline := map[string]ts.FileSet{
		"C++":        {"path/to/file.cpp": struct{}{}},
		"C":          {"path/to/file.c": struct{}{}},
		"JavaScript": {"path/to/file.js": struct{}{}},
		"TypeScript": {"path/to/file.ts": struct{}{}},
	}

	success1 := ts.FileSetUnion(baseline["C++"], baseline["JavaScript"])
	notExtracted1 := sarif.GetNotExtractedFiles(baseline, success1)
	require.Len(t, notExtracted1, 4)
	require.Len(t, notExtracted1["C"], 1)
	require.Len(t, notExtracted1["TypeScript"], 1)

	success2 := ts.FileSetUnion(baseline["C"], baseline["TypeScript"])
	notExtracted2 := sarif.GetNotExtractedFiles(baseline, success2)
	require.Len(t, notExtracted2, 4)
	require.Len(t, notExtracted2["C++"], 1)
	require.Len(t, notExtracted2["JavaScript"], 1)
}

func TestGetSuccessfullyExtractedFilesOnMergedRuns(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotificationsMultiRun.sarif")
	run, err := doc.Runs[0].Merge(doc.Runs[1])
	require.NoError(t, err)

	extracted, err := sarif.GetSuccessfullyExtractedFiles(run)
	require.NoError(t, err)
	require.Contains(t, extracted, "java")
	require.Contains(t, extracted, "js")

	require.Equal(t, 1, len(extracted["java"]))
	require.Equal(t, 1, len(extracted["js"]))
}

func TestGetBaselineExtractedFilesWithSublanguageFileCoverage(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-with-sublanguage-file-coverage.sarif")

	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.ElementsMatch(t, []string{"Java", "Kotlin"}, maps.Keys(baseline))

	require.Equal(t, 1, len(baseline["Java"]))
	require.Equal(t, true, baseline["Java"].Contains("path/to/file.java"))

	require.Equal(t, 2, len(baseline["Kotlin"]))
	require.Equal(t, true, baseline["Kotlin"].Contains("path/to/another/file.kt"))
	require.Equal(t, true, baseline["Kotlin"].Contains("path/to/a/third/file.kt"))
}

func TestGetExtractedFilesWithSublanguageFileCoverage(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-with-sublanguage-file-coverage.sarif")

	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, baseline)

	extracted, err := sarif.GetExtractedFiles(doc.Runs[0], baseline)
	require.NoError(t, err)
	require.NotEmpty(t, extracted)
	require.Equal(t, 2, len(extracted))

	require.Equal(t, 1, len(extracted["Java"]))
	require.Equal(t, true, extracted["Java"].Contains("path/to/file.java"))

	require.Equal(t, 1, len(extracted["Kotlin"]))
	require.Equal(t, true, extracted["Kotlin"].Contains("path/to/another/file.kt"))
}

func TestGetNotExtractedFilesWithSublanguageFileCoverage(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-with-sublanguage-file-coverage.sarif")
	success, err := sarif.GetSuccessfullyExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, success)

	baseline, err := sarif.GetBaselineExtractedFiles(doc.Runs[0])
	require.NoError(t, err)
	require.NotEmpty(t, baseline)

	allSuccess := ts.FileSetUnion(maps.Values(success)...)
	notExtracted := sarif.GetNotExtractedFiles(baseline, allSuccess)
	require.NotEmpty(t, notExtracted)
	require.ElementsMatch(t, []string{"Java", "Kotlin"}, maps.Keys(notExtracted))

	require.Equal(t, 0, len(notExtracted["Java"]))

	require.Equal(t, 1, len(notExtracted["Kotlin"]))
	require.Equal(t, true, notExtracted["Kotlin"].Contains("path/to/a/third/file.kt"))
}

func TestGetCodeQLExtractorErrors(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/codeql_extractor_errors.sarif")
	errorsMap := make(map[string]*v2_1_0_turboscan.Notification)
	notExtracted := ts.FileSet{"file.py": struct{}{}, "file2.py": struct{}{}, "file3.py": struct{}{}}

	err := sarif.GetCodeQLExtractorErrors(doc.Runs[0].Invocations[0].ToolExecutionNotifications[3], "", errorsMap, notExtracted)
	require.NoError(t, err)
	// errors without file paths are ignored
	require.Equal(t, 0, len(errorsMap))

	for _, notification := range doc.Runs[0].Invocations[0].ToolExecutionNotifications {
		err := sarif.GetCodeQLExtractorErrors(notification, "", errorsMap, notExtracted)
		require.NoError(t, err)
	}

	require.Equal(t, 2, len(errorsMap))
	// index.html is excluded because it is not in the notExtracted set
	require.ElementsMatch(t, []string{"file.py", "file2.py"}, maps.Keys(errorsMap))
}
