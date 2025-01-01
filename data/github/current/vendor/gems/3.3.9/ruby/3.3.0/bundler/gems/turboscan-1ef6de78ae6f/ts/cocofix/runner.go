package cocofix

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/twirp/clients/spokes"

	"github.com/pkg/errors"
)

type CachingFolder string

type CapiEnv string

const (
	CapiEnvProd CapiEnv = "prod"
	CapiEnvDev  CapiEnv = "dev"
)

func (c CapiEnv) String() string {
	return string(c)
}

type CapiModelName string

const (
	CapiModelNameDefault CapiModelName = "gpt-4-o-preview"
)

func (n CapiModelName) String() string {
	return string(n)
}

type CocofixRunner struct {
	throttler     *Throttler
	capiEnv       CapiEnv
	capiUserID    uint64
	capiKey       string
	capiModelName string
	ghAppToken    string
	sarifInput    string
	filepaths     []string

	filesums map[string]ts.Sha1Checksum
	caching  CachingFolder
}

func NewCocofixRunner(throttler *Throttler, capiEnv CapiEnv, capiKey string, capiUserID uint64, ghAppToken string, capiModelName string) ts.FixGenerator {

	return &CocofixRunner{
		throttler:     throttler,
		capiEnv:       capiEnv,
		capiUserID:    capiUserID,
		capiKey:       capiKey,
		capiModelName: capiModelName,
		ghAppToken:    ghAppToken,
		filesums:      make(map[string]ts.Sha1Checksum),
	}
}

var configurationFileNames = []string{
	// JavaScript/TypeScript
	"package.json",
	// Python
	"requirements.txt", "Pipfile", "setup.py", "pyproject.toml",
	// Java
	"pom.xml", "build.gradle", "build.gradle.kts",
	// Go
	"go.mod",
	// Ruby
	"Gemfile",
}

func IsConfigurationFile(f string) bool {
	baseName := filepath.Base(f)
	for _, cf := range configurationFileNames {
		if baseName == cf {
			return true
		}
	}
	return false
}

// FindConfigurationFiles finds all configuration files in the same directory as,
// or any parent directory of, one of the given source files.
func FindConfigurationFiles(sourceFiles []string) []string {
	// map to avoid duplicates
	additionalFiles := make(map[string]bool)
	for _, f := range sourceFiles {
		dir := filepath.Dir(f)
		// iterate over dir and all parent directories
		for {
			for _, cf := range configurationFileNames {
				configurationFilePath := filepath.Join(dir, cf)
				additionalFiles[configurationFilePath] = true
			}

			// stop if we reached the root directory
			if dir == "." || dir == "/" {
				break
			}
			dir = filepath.Dir(dir)
		}
	}

	files := make([]string, 0, len(additionalFiles))
	for f := range additionalFiles {
		files = append(files, f)
	}

	return files
}

// sanitizeFilePath checks if the file path is in /tmp/autofix
func sanitizeFilePath(safeDir string, fp string) (string, error) {
	// sanitize file path
	absFilePath, err := filepath.Abs(fp)
	if err != nil {
		return "", err
	}
	if strings.HasPrefix(absFilePath, safeDir) {
		return absFilePath, nil
	}
	return "", errors.Errorf("file path %s is not in /tmp/autofix", absFilePath)
}

func (c *CocofixRunner) setupInputSrc(ctx context.Context, dir string, downloadFunc ts.DownloadFilesFunc, repoID ts.RepositoryEID, workload ts.ThrottlerWorkload) (string, error) {
	srcInputDir := filepath.Join(dir, "src")
	err := os.Mkdir(srcInputDir, 0700)
	if err != nil {
		return "", &TransientError{Err: errors.Wrap(err, "error creating the src directory")}
	}

	files := make([]string, len(c.filepaths))
	copy(files, c.filepaths)
	configFiles := FindConfigurationFiles(files)
	files = append(files, configFiles...)

	var b []byte
	for _, f := range files {
		appctx.Stats(ctx).Counter("cocofix_runner.downloaded_files", stats.Tags{"workload": workload.String()}, 1)
		b, err = downloadFunc(ctx, f)
		if err != nil {
			// Configuration files are optional. If a configuration file is not found, we can still continue
			if IsConfigurationFile(f) {
				appctx.Logger(ctx).WithError(err).Info("error downloading a configuration file from spokes. Skipping it", repoID.AsKVP(), kvp.String("file", f))
				continue
			}

			if errors.Is(err, spokes.ErrFileNotFound) {
				appctx.Logger(ctx).WithError(err).Error("spokes couldn't find this file", repoID.AsKVP(), kvp.String("file", f))
				return "", &NonRetriableError{err: errors.Wrap(err, "error downloading file")}
			}
			appctx.Logger(ctx).WithError(err).Info("error downloading a file from spokes", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error downloading file")}
		}

		// sanitize file path if not a configuration file
		destFp, err := sanitizeFilePath(srcInputDir, filepath.Join(srcInputDir, f))
		if err != nil {
			appctx.Logger(ctx).Info("error sanitizing input file path", kvp.Err(err), kvp.String("file", f))
			return "", &NonRetriableError{err: errors.Wrap(err, "error sanitizing input file path")}
		}

		err = os.MkdirAll(filepath.Dir(destFp), 0700)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Info("error creating the directory", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error creating the directory")}
		}

		err = os.WriteFile(destFp, b, 0644)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Info("error writing the file", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error writing the file")}
		}
		c.filesums[f] = ts.BuildFileChecksum(b)
	}

	return srcInputDir, nil
}

func (c *CocofixRunner) setupInputs(ctx context.Context, downloadFunc ts.DownloadFilesFunc, repoID ts.RepositoryEID, workload ts.ThrottlerWorkload) (string, string, string, error) {
	defer c.emitDistribution(ctx, "SetupInputs")()
	dir, err := os.MkdirTemp("", "autofix")
	if err != nil {
		return "", "", "", &TransientError{Err: errors.Wrap(err, "error creating the cocofix inputs directory")}
	}

	// Input source code
	srcInputDir, err := c.setupInputSrc(ctx, dir, downloadFunc, repoID, workload)
	if err != nil {
		return dir, "", "", err
	}

	// Input sarif file
	sarifPath := filepath.Join(dir, "input.sarif") // There is no need to sanitize this path as it is fully under our control
	err = os.WriteFile(sarifPath, []byte(c.sarifInput), 0600)
	if err != nil {
		return dir, "", "", &TransientError{Err: errors.Wrap(err, "error while writing the sarif file")}
	}

	return dir, sarifPath, srcInputDir, nil
}

// GenerateFix Generates a fix calling cocofix tool.
// It creates a temporary dir to host the inputs and outputs.
//
// $dir/input.sarif: the sarif with the physical alert
// $dir/src/: directory with the source code related to the alerts in the sarif file
// $dir/output.json: the output json file with the fixes
func (c *CocofixRunner) GenerateFix(
	ctx context.Context,
	tool ts.ToolName,
	toolVersion string,
	sfa *ts.SuggestedFixAlert,
	proximaEnv bool,
	downloadFunc ts.DownloadFilesFunc,
	userID uint64,
	workload ts.ThrottlerWorkload) (ts.GenerateFixResult, error) {

	sarifBuilderOpts := SarifBuilderOpts{}

	ctx = appctx.WithLogger(ctx, appctx.Logger(ctx).Named("cocofix_runner"))

	// If the repository has code_scanning_suggested_all_queries FF enabled, we will not
	// enforce default rules only
	// So we can test new rules and queries
	// Important: AllowNonDefaultRules=true option should only be used under controlled conditions
	// otherwise user's input rules might be executed
	if flipper.HasSuggestedFixAllQueries(ctx, sfa.RepositoryID) {
		sarifBuilderOpts.AllowNonDefaultRules = true
	}

	appctx.Stats(ctx).Distribution("cocofix_runner.alerts", stats.Tags{"workload": workload.String()}, 1)
	sarifInput, filepaths, err := c.buildSarifInput(ctx, &ToolInfo{
		ToolName:    tool.String(),
		ToolVersion: toolVersion,
	}, sfa.PhysicalAlert, sarifBuilderOpts)
	if err != nil {
		return ts.GenerateFixResult{}, err
	}
	c.sarifInput, c.filepaths = sarifInput, filepaths

	resp, err := c.generateFixes(ctx, sfa.RepositoryID, c.capiEnv, proximaEnv, downloadFunc, workload)
	if err != nil {
		return ts.GenerateFixResult{}, err
	}

	if len(resp) != 1 {
		return ts.GenerateFixResult{}, errors.Errorf("cocofix returns %d fixes", len(resp))
	}
	output := resp[0]
	return c.buildGenerateFixResponse(ctx, output, sfa.RepositoryID, c.filesums)
}

func (c *CocofixRunner) generateFixes(ctx context.Context, repoID ts.RepositoryEID, capiEnv CapiEnv, proximaEnv bool, downloadFunc ts.DownloadFilesFunc, workload ts.ThrottlerWorkload) (CocofixResponse, error) {
	dir, sarifPath, srcInputDir, err := c.setupInputs(ctx, downloadFunc, repoID, workload)
	defer os.RemoveAll(dir)
	if err != nil {
		return nil, err
	}

	if !proximaEnv {
		err := c.throttler.WaitOnThrottler(ctx, workload)
		if err != nil {
			return nil, err
		}
	}

	of := filepath.Join(dir, "output.json")
	model := fmt.Sprintf("capi-%s", capiEnv)
	args := []string{
		"--sarif",
		sarifPath,
		"--source-root",
		srcInputDir,
		"--output",
		of,
		"--format", "json",
		"--no-retry",
		"--diff-style", "diff",
		"--quiet",
		"--model",
		model,
		"--stream",
	}

	if c.caching != "" {
		args = append(args, "--cache", string(c.caching))
	} else {
		args = append(args, "--no-cache")
	}

	if flipper.HasSuggestedFixAllQueries(ctx, repoID) {
		args = append(args, "--dev")
	}

	cmd := exec.CommandContext(ctx, "cocofix", args...)

	slug := tenant.GetTenant(ctx)

	capiModelName := c.capiModelName
	if capiModelName == "" {
		capiModelName = CapiModelNameDefault.String()
	}

	cmd.Env = append(
		os.Environ(),
		fmt.Sprintf("CAPI_%s_KEY=%s", strings.ToUpper(capiEnv.String()), c.capiKey),
		fmt.Sprintf("GH_TOKEN=%s", c.ghAppToken),
		fmt.Sprintf("CAPI_MODEL_NAME=%s", capiModelName),
	)

	if proximaEnv && slug != "" {
		url := fmt.Sprintf("https://copilot-api.%s.ghe.com", slug)
		cmd.Env = append(
			cmd.Env,
			fmt.Sprintf("CAPI_URL=%s", url),
		)
	}

	// Execute script command and capture the output and error streams
	start := time.Now()

	var stderr, stdout bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err = cmd.Run()

	sarifBuf := bytes.NewBufferString(c.sarifInput)
	truncateBuffers(6*1024, sarifBuf, &stderr, &stdout) // limit to 6KB total
	appctx.Stats(ctx).DistributionMs("cocofix_runner.call", stats.Tags{
		"error": strconv.FormatBool(err != nil),
	}, time.Since(start))

	if err != nil {
		appctx.Logger(ctx).Error("Got error from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("stdout", stdout.String()),
			kvp.String("stderr", stderr.String()),
			kvp.String("sarifInput", sarifBuf.String()),
		)

		if cmd.ProcessState.ExitCode() == 255 {
			// we should retry if process failed with 255 exit code
			return nil, &TransientError{
				Err: err,
			}
		}

		appctx.Report(ctx, errors.Wrap(err, "Got error from cocofix"), nil)
		return nil, &NonRetriableError{
			err: err,
			msg: "Failed to execute cocofix script",
		}
	}

	dat, err := os.ReadFile(of)
	if err != nil {
		appctx.Logger(ctx).Error("Failed to read output file from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("stdout", stdout.String()),
			kvp.String("stderr", stderr.String()),
			kvp.String("sarifInput", sarifBuf.String()),
		)
		appctx.Report(ctx, errors.Wrap(err, "Failed to read output file from cocofix"), nil)
		return nil, &NonRetriableError{
			err: err,
			msg: fmt.Sprintf("Failed to read output file from %s", of),
		}
	}

	resp, err := parseResponseJson(dat)
	if err != nil {
		appctx.Logger(ctx).Error("Failed to parse json output from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.String("response", sanitizeJsonString(string(dat))),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("stdout", stdout.String()),
			kvp.String("stderr", stderr.String()),
			kvp.String("sarifInput", sarifBuf.String()),
		)
		appctx.Report(ctx, errors.Wrap(err, "Failed to parse json output from cocofix"), nil)
		return nil, &NonRetriableError{
			err: err,
			msg: "Failed to parse json output from cocofix",
		}
	}

	appctx.Logger(ctx).Info("cocofix ran with success.",
		kvp.String("scriptPath", cmd.Path),
		kvp.Strings("scriptArgs", cmd.Args),
		kvp.String("response", sanitizeJsonString(string(dat))),
		kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
		kvp.String("stdout", stdout.String()),
		kvp.String("stderr", stderr.String()),
	)

	return resp, nil
}

func (c *CocofixRunner) emitDistribution(ctx context.Context, method string) func() {
	start := time.Now()
	return func() {
		appctx.Stats(ctx).DistributionMs("cocofix_runner.setup", stats.Tags{"method": method}, time.Since(start))
	}
}
