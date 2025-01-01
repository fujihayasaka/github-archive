package cocofix

import (
	"context"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

func Test_setupInputsForDependabot(t *testing.T) {
	c := &CocofixRunner{
		filesums: make(map[string]ts.Sha1Checksum),
	}

	sarifInput := "{sarif: 1}"
	filepaths := []string{"index.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte("foobar"), nil
	}
	dir, sarifPath, srcInputDir, err := c.setupInputsForDependabot(ctx, downloadFunc, ts.RepositoryEID(1), sarifInput, filepaths)
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	d2, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	require.Equal(t, "{sarif: 1}", string(d2))
	require.Equal(t, filepath.Join(dir, "src"), srcInputDir)

	d2, err = os.ReadFile(filepath.Join(srcInputDir, "package.json"))
	require.NoError(t, err)
	require.Equal(t, "foobar", string(d2))

	require.NotNil(t, c.filesums)
}

func Test_setupInputSrcForDependabot(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"index.js", "ts/foo.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, c.filesums)

	inputFiles := map[string]bool{
		"ts/foo.js": true,
		"index.js":  true,
	}
	// calculate no of files in srdDir
	fileCount := 0
	err = filepath.Walk(srcDir, func(path string, info fs.FileInfo, err error) error {
		require.NoError(t, err)
		// test downloadFunc returns content for any file, so we create all config files
		if !info.IsDir() && !IsConfigurationFile(path) {
			fileCount++
			require.True(t, inputFiles[strings.TrimPrefix(path, srcDir+"/")])
		}
		return nil
	})
	require.NoError(t, err)
	require.Equal(t, 2, fileCount)

	tests := []struct {
		name     string
		filePath string
		content  string
	}{
		{"ts/foo.js", "ts/foo.js", "ts/foo.jscontent"},
		{"index.js", "index.js", "index.jscontent"},
	}
	configFiles := FindConfigurationFiles(maps.Keys(inputFiles))
	for _, cName := range configFiles {
		tests = append(tests, struct {
			name     string
			filePath string
			content  string
		}{cName, cName, cName + "content"})
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d, err := os.ReadFile(filepath.Join(srcDir, tt.filePath))
			require.NoError(t, err)
			require.Equal(t, tt.content, string(d))
		})
	}
}

func Test_setupInputSrcForDependabot_SanitizeError(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"../../etc/passwd"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.Error(t, err)
	require.ErrorContains(t, err, "error sanitizing input file path")
}

func Test_setupInputSrcForDependabot_PackageJsonFilesOnlyDownloadedOnce(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	alreadyDownloaded := make(map[string]bool)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"index.js", "foo.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		require.False(t, alreadyDownloaded[filepath])
		alreadyDownloaded[filepath] = true
		return []byte("content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, c.filesums)
}

func Test_setupInputSrcForDependabot_WithPackageJsonInRootDir(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"src/foo.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, c.filesums)

	// check that package.json is downloaded even though there are no
	// files in the same directory as it
	d, err := os.ReadFile(filepath.Join(srcDir, "package.json"))
	require.NoError(t, err)
	require.Equal(t, "package.jsoncontent", string(d))
}

func Test_setupInputSrcForDependabot_WithRequirementsTxtInRootDir(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"src/main.py"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, sums)

	// check that requirements.txt is downloaded even though there are no
	// files in the same directory as it
	d, err := os.ReadFile(filepath.Join(srcDir, "requirements.txt"))
	require.NoError(t, err)
	require.Equal(t, "requirements.txtcontent", string(d))
}

func Test_setupInputSrcForDependabot_WithPipfile(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		filesums: sums,
	}

	filepaths := []string{"tst.py"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, sums)

	// check that Pipfile is downloaded
	d, err := os.ReadFile(filepath.Join(srcDir, "Pipfile"))
	require.NoError(t, err)
	require.Equal(t, "Pipfilecontent", string(d))
}

func Test_setupInputSrcForDependabot_WithNoPackageJson(t *testing.T) {
	c := &CocofixRunner{
		filesums: make(map[string]ts.Sha1Checksum),
	}
	filepaths := []string{"index.js", "ts/foo.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		if filepath == "package.json" {
			return []byte{}, spokes.ErrFileNotFound
		}
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)
	require.NotNil(t, c.filesums)

	_, err = os.ReadFile(filepath.Join(srcDir, "package.json"))
	require.Error(t, err, "package.json should not exist")
	d, err := os.ReadFile(filepath.Join(srcDir, "index.js"))
	require.NoError(t, err)
	require.Equal(t, "index.jscontent", string(d))
}

func Test_setupInputSrcForDependabot_WithNoExistentFiles(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)

	c := &CocofixRunner{
		filesums: sums,
	}
	filepaths := []string{"foo.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, f string) ([]byte, error) {
		return os.ReadFile(filepath.Join(testdataPath(t), "src", f))
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.Error(t, err)
	require.Empty(t, sums)
}

func Test_setupInputSrcForDependabot_Filesums(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")
	sums := make(map[string]ts.Sha1Checksum)

	c := &CocofixRunner{
		filesums: sums,
	}
	filepaths := []string{"index.js"}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, f string) ([]byte, error) {
		b, err := os.ReadFile(filepath.Join(tdPath, "src", f))
		var fe *fs.PathError
		if err != nil && errors.As(err, &fe) {
			// return a mock spokes error to mimic real world spokes client error
			return b, spokes.ErrFileNotFound
		}
		return b, err
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrcForDependabot(ctx, dir, downloadFunc, ts.RepositoryEID(1), filepaths)
	require.NoError(t, err)

	require.Equal(t, "af68cdcd9a0b655d1d35ad30ed565875fe3dd49c", fmt.Sprintf("%x", c.filesums["index.js"]))
	require.Equal(t, "f483937159196703558e4a3525a304e84f288303", fmt.Sprintf("%x", c.filesums["package.json"]))
}

func TestDependabotBreakingChange(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.DependabotAutofix)

	output := runCoCoFixForDependabot(t, ctx, "dependabot.sarif", ts.CapiInteraction{}, "src/index.js", "src/index.test.js", "package.json")

	require.Equal(t, "fix", output[0].Outcome.Kind, output)
	require.Equal(t, "valid", output[0].Outcome.Assessment.Outcome)

	alert := output[0].Alert
	require.Equal(t, respAlert{
		Message: "Cannot use import statement outside a module",
		RuleId:  "js/breaking-change",
		Location: Location{
			Path:        "package.json",
			StartLine:   10,
			StartColumn: 1,
			EndLine:     10,
			EndColumn:   17,
		},
	}, alert)

	expected := map[string]string{
		"package.json":      "--- a/package.json\n+++ b/package.json\n@@ -5,2 +5,3 @@\n   \"main\": \"src/index.js\",\n+  \"type\": \"module\",\n   \"scripts\": {\n",
		"src/index.js":      "--- a/src/index.js\n+++ b/src/index.js\n@@ -1,2 +1,2 @@\n-const axios = require('axios');\n+import axios from 'axios';\n \n@@ -12,2 +12,2 @@\n \n-module.exports = fetchData;\n+export default fetchData;\n",
		"src/index.test.js": "--- a/src/index.test.js\n+++ b/src/index.test.js\n@@ -1,3 +1,3 @@\n-const fetchData = require('./index');\n-const axios = require('axios');\n+import fetchData from './index';\n+import axios from 'axios';\n jest.mock('axios');\n",
	}
	for _, d := range output[0].Outcome.Diffs {
		require.Equal(t, expected[d.Path], d.Diff)
	}
}

func TestWithoutSourceFiles(t *testing.T) {
	ctx := context.Background()
	output := runCoCoFixForDependabot(t, ctx, "../ccr-case.sarif", ts.CapiInteraction{ID: "7c041efdf223886a366132bf3f4973ea62613b777fdd86f7215608e98b4546d1", Type: "code-review"})

	require.Equal(t, "fix", output[0].Outcome.Kind)
	c := &CocofixRunner{}
	r, err := c.buildGenerateFixResponse(ctx, output[0], ts.RepositoryEID(1), make(map[string]ts.Sha1Checksum), ts.CapiIntegrationCCR, false)
	require.NoError(t, err)

	require.NotEmpty(t, r.SuggestedFix.Files)
	require.Equal(t, "--- a/violation.rb\n+++ b/violation.rb\n@@ -2,3 +2,3 @@\n value = false\n-if not value\n+unless value\n puts \"Value is false\"\n", string(r.SuggestedFix.Files[0].DiffContent))
	require.Equal(t, ts.Sha1Checksum{}, r.SuggestedFix.Files[0].FileChecksum) // empty value
}

func TestCustomIntegrationId(t *testing.T) {
	ctx := context.Background()
	cwd, err := os.Getwd()
	require.NoError(t, err)

	cfg, err := config.Load()
	require.NoError(t, err)
	capiConfig := TestCapiConfig(cfg, false)
	capiConfig.integrations[ts.CapiIntegrationCCR] = CapiIntegration{
		Key: "fake",
		ID:  "ghas-code-scanning-autofix-dev",
	}
	c := &CocofixRunner{
		capiConfig: capiConfig,
		filesums:   make(map[string]ts.Sha1Checksum),
	}

	tdPath := filepath.Join(cwd, "testdata")
	sarifPath := filepath.Join(tdPath, "ccr-case.sarif")
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)

	cfgLogger, err := cfg.NewLogger()
	require.NoError(t, err)

	output, err := c.generateDependabotFix(appctx.WithLogger(ctx, cfgLogger), ts.RepositoryEID(42), nil, string(data), []string{}, ts.CapiIntegrationCCR, ts.CapiInteraction{})
	var ne *NonRetriableError
	if errors.As(err, &ne) {
		require.NoError(t, err)
	}
	require.NotNil(t, output)
	require.Equal(t, "Unauthorized", output[0].Outcome.Error)
}

// runCoCoFix runs CoCoFix with the given sarif file and filepaths in the given srcDir, which must be under
// the testdata directory.
func runCoCoFixForDependabot(t *testing.T, ctx context.Context, sarifFileName string, interaction ts.CapiInteraction, filepaths ...string) CocofixResponse {
	t.Helper()

	cfg, err := config.Load()

	require.NoError(t, err)
	logger := log.NewNullLogger()

	cwd, err := os.Getwd()
	require.NoError(t, err)

	expectedCoCoFixVersion := getAIVersion()

	tdPath := filepath.Join(cwd, "testdata", "dependabot")

	sarifPath := filepath.Join(tdPath, sarifFileName)
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)

	// using same cache dir
	cf := filepath.Join(cwd, "testdata", "cache")

	var capiConfig *CapiConfig
	if *real_creds {
		if cfg.CapiGhasHMACKey == "" || cfg.GitHubAppToken == "" {
			t.Error("missing credentials.")
		}
		capiConfig = TestCapiConfig(cfg, true)
	} else {
		capiConfig = TestCapiConfig(cfg, false)
	}

	cocofixThrottler, err := NewThrottler(logger, cfg.CapiThrottlerUrl)
	if err != nil {
		t.Error(err)
	}

	c := &CocofixRunner{
		capiConfig: capiConfig,
		throttler:  cocofixThrottler,
		caching:    CachingFolder(cf),
		filesums:   make(map[string]ts.Sha1Checksum),
	}

	downloadFunc := func(ctx context.Context, f string) ([]byte, error) {
		b, err := os.ReadFile(filepath.Join(tdPath, f))
		var fe *fs.PathError
		if err != nil && errors.As(err, &fe) {
			// return a mock spokes error to mimic real world spokes client error
			return b, spokes.ErrFileNotFound
		}
		return b, err
	}

	cfgLogger, err := cfg.NewLogger()
	require.NoError(t, err)

	output, err := c.generateDependabotFix(appctx.WithLogger(ctx, cfgLogger), ts.RepositoryEID(42), downloadFunc, string(data), filepaths, ts.CapiIntegrationDependabot, interaction)
	var ne *NonRetriableError
	if errors.As(err, &ne) {
		require.NoError(t, err)
	}
	require.NotNil(t, output)
	require.NotNil(t, c.filesums)

	actualCoCoFixVersion := output[0].CoCoFixVersion
	require.Equal(t, expectedCoCoFixVersion, actualCoCoFixVersion)

	return output
}
