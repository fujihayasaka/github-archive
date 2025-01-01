package cocofix

import (
	"context"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

func TestSetupInputs(t *testing.T) {
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"index.js"},
		filesums:   make(map[string]ts.Sha1Checksum),
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte("foobar"), nil
	}
	dir, sarifPath, srcInputDir, err := c.setupInputs(ctx, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	d2, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	require.Equal(t, "{sarif: 1}", string(d2))
	require.Equal(t, filepath.Join(dir, "src"), srcInputDir)

	d2, err = os.ReadFile(filepath.Join(srcInputDir, "package.json"))
	require.NoError(t, err)
	require.Equal(t, "foobar", string(d2))
}

func TestSetupInputSrc(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"index.js", "ts/foo.js"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

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

func TestSetupInputSrcSanitizeError(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"../../etc/passwd"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.Error(t, err)
	require.ErrorContains(t, err, "error sanitizing input file path")
}

func TestSetupInputSrcPackageJsonFilesOnlyDownloadedOnce(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	alreadyDownloaded := make(map[string]bool)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"index.js", "foo.js"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		require.False(t, alreadyDownloaded[filepath])
		alreadyDownloaded[filepath] = true
		return []byte("content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)
}

func TestSetupInputSrcWithPackageJsonInRootDir(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"src/foo.js"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	// check that package.json is downloaded even though there are no
	// files in the same directory as it
	d, err := os.ReadFile(filepath.Join(srcDir, "package.json"))
	require.NoError(t, err)
	require.Equal(t, "package.jsoncontent", string(d))
}

func TestSetupInputSrcWithRequirementsTxtInRootDir(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"src/main.py"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	// check that requirements.txt is downloaded even though there are no
	// files in the same directory as it
	d, err := os.ReadFile(filepath.Join(srcDir, "requirements.txt"))
	require.NoError(t, err)
	require.Equal(t, "requirements.txtcontent", string(d))
}

func TestSetupInputSrcWithPipfile(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"tst.py"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, filepath string) ([]byte, error) {
		return []byte(filepath + "content"), nil
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	srcDir, err := c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	// check that Pipfile is downloaded
	d, err := os.ReadFile(filepath.Join(srcDir, "Pipfile"))
	require.NoError(t, err)
	require.Equal(t, "Pipfilecontent", string(d))
}

func TestSetupInputSrcWithNoPackageJson(t *testing.T) {
	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"index.js", "ts/foo.js"},
		filesums:   make(map[string]ts.Sha1Checksum),
	}

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

	srcDir, err := c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	_, err = os.ReadFile(filepath.Join(srcDir, "package.json"))
	require.Error(t, err, "package.json should not exist")
	d, err := os.ReadFile(filepath.Join(srcDir, "index.js"))
	require.NoError(t, err)
	require.Equal(t, "index.jscontent", string(d))
}

func TestSetupInputSrcWithNoExistentFiles(t *testing.T) {
	sums := make(map[string]ts.Sha1Checksum)

	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"foo.js"},
		filesums:   sums,
	}

	ctx := context.Background()
	downloadFunc := func(ctx context.Context, f string) ([]byte, error) {
		return os.ReadFile(filepath.Join(testdataPath(t), "src", f))
	}
	dir, err := os.MkdirTemp("", "autofix")
	require.NoError(t, err)
	defer os.RemoveAll(dir)

	_, err = c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.Error(t, err)
	require.Empty(t, sums)
}

func TestSetupInputSrcFilesums(t *testing.T) {
	cwd, err := os.Getwd()
	require.NoError(t, err)
	tdPath := filepath.Join(cwd, "testdata")
	sums := make(map[string]ts.Sha1Checksum)

	c := &CocofixRunner{
		sarifInput: "{sarif: 1}",
		filepaths:  []string{"index.js"},
		filesums:   sums,
	}

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

	_, err = c.setupInputSrc(ctx, dir, downloadFunc, ts.RepositoryEID(1), ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	require.Equal(t, "af68cdcd9a0b655d1d35ad30ed565875fe3dd49c", fmt.Sprintf("%x", sums["index.js"]))
	require.Equal(t, "f483937159196703558e4a3525a304e84f288303", fmt.Sprintf("%x", sums["package.json"]))
}

var real_creds = flag.Bool("real_creds", false, "Force CoCoFix to use real credentials.")

// runCoCoFix runs CoCoFix with the given sarif file and filepaths in the given srcDir, which must be under
// the testdata directory.
func runCoCoFix(t *testing.T, ctx context.Context, sarifFileName string, srcDir string, proximaEnv bool, filepaths ...string) CocofixResponse {
	t.Helper()

	cfg, err := config.Load()

	require.NoError(t, err)
	logger := log.NewNullLogger()

	cwd, err := os.Getwd()
	require.NoError(t, err)

	expectedCoCoFixVersion := getAIVersion()

	tdPath := filepath.Join(cwd, "testdata")

	sarifPath := filepath.Join(tdPath, sarifFileName)
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)

	cf := filepath.Join(tdPath, "cache")
	ck := cfg.CapiDevKey
	ghAppToken := cfg.GitHubAppToken
	capiModelName := CapiModelName(cfg.CapiModelName)
	if !*real_creds {
		ck = "dev"
		ghAppToken = "fake"
	}

	if ck == "" || ghAppToken == "" {
		t.Error("missing credentials.")
	}

	cocofixThrottler, err := NewThrottler(logger, cfg.CapiThrottlerUrl)
	if err != nil {
		t.Error(err)
	}

	c := &CocofixRunner{
		throttler:     cocofixThrottler,
		capiUserID:    cfg.CapiUserID,
		capiKey:       ck,
		capiModelName: capiModelName.String(),
		ghAppToken:    ghAppToken,
		sarifInput:    string(data),
		filepaths:     filepaths,
		filesums:      make(map[string]ts.Sha1Checksum),
		caching:       CachingFolder(cf),
	}

	downloadFunc := func(ctx context.Context, f string) ([]byte, error) {
		b, err := os.ReadFile(filepath.Join(tdPath, srcDir, f))
		var fe *fs.PathError
		if err != nil && errors.As(err, &fe) {
			// return a mock spokes error to mimic real world spokes client error
			return b, spokes.ErrFileNotFound
		}
		return b, err
	}

	output, err := c.generateFixes(ctx, ts.RepositoryEID(42), CapiEnvDev, proximaEnv, downloadFunc, ts.ThrottlerWorkload_HIGH)
	var ne *NonRetriableError
	if errors.As(err, &ne) {
		require.NoError(t, err)
	}
	require.NotNil(t, output)

	actualCoCoFixVersion := output[0].CoCoFixVersion
	require.Equal(t, expectedCoCoFixVersion, actualCoCoFixVersion)

	return output
}

func TestFixSyntheticXssWithTenant(t *testing.T) {
	ctx := tenant.TenantContext(context.Background(), "staffship-01")

	output := runCoCoFix(t, ctx, "reflected-xss.sarif", "src", true, "index.js")
	slug := tenant.GetTenant(ctx)

	require.Equal(t, "fix", output[0].Outcome.Kind, output)
	require.Equal(t, "valid", output[0].Outcome.Assessment.Outcome)

	require.Equal(t, "staffship-01", slug)

	alert := output[0].Alert
	require.Equal(t, respAlert{
		Message: "Cross-site scripting vulnerability due to a user-provided value.",
		RuleId:  "js/reflected-xss",
		Location: Location{
			Path:        "index.js",
			StartLine:   4,
			StartColumn: 37,
			EndLine:     4,
			EndColumn:   64,
		},
	}, alert)
}

func TestFixSyntheticXss(t *testing.T) {
	ctx := context.Background()

	output := runCoCoFix(t, ctx, "reflected-xss.sarif", "src", false, "index.js")

	require.Equal(t, "fix", output[0].Outcome.Kind, output)
	require.Equal(t, "valid", output[0].Outcome.Assessment.Outcome)

	alert := output[0].Alert
	require.Equal(t, respAlert{
		Message: "Cross-site scripting vulnerability due to a user-provided value.",
		RuleId:  "js/reflected-xss",
		Location: Location{
			Path:        "index.js",
			StartLine:   4,
			StartColumn: 37,
			EndLine:     4,
			EndColumn:   64,
		},
	}, alert)
}

func TestFixUnsupportedQuery(t *testing.T) {
	ctx := context.Background()
	output := runCoCoFix(t, ctx, "made-up-alert.sarif", "src", false, "index.js")

	outcome := output[0].Outcome
	require.Equal(t, "error", outcome.Kind)
	require.Equal(t, "Excluded query", outcome.Error)
	require.Equal(t, "Fixes for js/a-custom-rule are not supported", outcome.Description)
	require.Equal(t, false, outcome.Transient)
	require.Equal(t, OutcomeSeverity_LOW, outcome.Severity)
}

func TestFixUnsupportedTool(t *testing.T) {
	ctx := context.Background()
	output := runCoCoFix(t, ctx, "made-up-tool.sarif", "src", false, "index.js")

	outcome := output[0].Outcome
	require.Equal(t, "error", outcome.Kind)
	require.Equal(t, "unsupported tool", outcome.Error)
	require.Contains(t, outcome.Description, "Made Up Tool is not one of")
	require.Equal(t, false, outcome.Transient)
	require.Equal(t, OutcomeSeverity_LOW, outcome.Severity)
}

func TestFixUnsupportedQueryWhenFeatureIsEnabled(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningSuggestedFixAllQueries)
	output := runCoCoFix(t, ctx, "made-up-alert.sarif", "src", false, "index.js")

	require.Equal(t, "fix", output[0].Outcome.Kind, output)
	require.Equal(t, "valid", output[0].Outcome.Assessment.Outcome)

	alert := output[0].Alert
	require.Equal(t, respAlert{
		Message: "Result from custom rule",
		RuleId:  "js/a-custom-rule",
		Location: Location{
			Path:        "index.js",
			StartLine:   4,
			StartColumn: 37,
			EndLine:     4,
			EndColumn:   64,
		},
	}, alert)
}
