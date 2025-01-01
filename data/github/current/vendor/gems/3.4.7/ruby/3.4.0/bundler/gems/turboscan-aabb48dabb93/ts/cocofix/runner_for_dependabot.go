package cocofix

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/pkg/errors"
)

func (c *CocofixRunner) GenerateDependabotFix(
	ctx context.Context,
	sarif string,
	filePaths []string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	integration ts.CapiIntegrationType,
	interaction ts.CapiInteraction,
) (ts.GenerateFixResult, error) {

	resp, err := c.generateDependabotFix(ctx, repoID, downloadFunc, sarif, filePaths, integration, interaction)
	if err != nil {
		return ts.GenerateFixResult{}, err
	}

	if len(resp) != 1 {
		return ts.GenerateFixResult{}, errors.Errorf("cocofix returns %d fixes", len(resp))
	}
	output := resp[0]
	return c.buildGenerateFixResponse(ctx, output, repoID, c.filesums, integration, false)
}

func (c *CocofixRunner) generateDependabotFix(
	ctx context.Context,
	repoID ts.RepositoryEID,
	downloadFunc ts.DownloadFilesFunc,
	sarif string,
	filePaths []string,
	integration ts.CapiIntegrationType,
	interaction ts.CapiInteraction,
) (CocofixResponse, error) {

	// 1. setup input sources - download files from spokes, make input source dir and save sarif file
	dir, sarifPath, srcInputDir, err := c.setupInputsForDependabot(ctx, downloadFunc, repoID, sarif, filePaths)
	defer os.RemoveAll(dir)
	if err != nil {
		return nil, err
	}

	// 2. build cocofix cli arguments
	of := filepath.Join(dir, "output.json")
	args := []string{
		"--sarif",
		sarifPath,
		"--output",
		of,
		"--format", "json",
		"--no-retry",
		"--diff-style", "diff",
		"--quiet",
		"--model",
		AIModel,
		"--stream",
		"--dev",
	}

	if srcInputDir != "" {
		args = append(args, "--source-root", srcInputDir)
	}

	if c.caching != "" {
		args = append(args, "--cache", string(c.caching))
	} else {
		args = append(args, "--no-cache")
	}

	if interaction.ID != "" {
		args = append(args, "--interaction-id", interaction.ID)
	}

	if interaction.Type != "" {
		args = append(args, "--interaction-type", interaction.Type)
	}

	i, err := c.capiConfig.GetIntegrationEnv(integration)
	if err != nil {
		return nil, err
	}

	cmd := exec.CommandContext(ctx, "cocofix", args...)

	// 3. build env vars for cocofix
	cmd.Env = append(
		os.Environ(),
		fmt.Sprintf("GH_TOKEN=%s", c.capiConfig.ghAppToken),
		fmt.Sprintf("CAPI_MODEL_NAME=%s", c.capiConfig.capiModelName),
		fmt.Sprintf("CAPI_PROD_KEY=%s", i.Key),
	)

	if i.ID != "" {
		cmd.Env = append(cmd.Env, fmt.Sprintf("CAPI_INTEGRATION_ID=%s", i.ID))
	}

	slug := tenant.GetTenant(ctx)
	if c.proximaEnv && slug != "" {
		url := fmt.Sprintf("https://copilot-api.%s.ghe.com", slug)
		cmd.Env = append(
			cmd.Env,
			fmt.Sprintf("CAPI_URL=%s", url),
		)
	}

	// 4. execute script command and capture the output and error streams
	start := time.Now()

	if w, ok := appctx.Logger(ctx).WithFields(kvp.Bool("cocofix.stdout", true)).(log.ToWriter); ok {
		writer := w.Writer()
		defer writer.Close()
		cmd.Stdout = writer
	} else {
		return nil, errors.New("stdout logger does not adhere to log.ToWriter interface")
	}
	if w, ok := appctx.Logger(ctx).WithFields(kvp.Bool("cocofix.stderr", true)).(log.ToWriter); ok {
		writer := w.Writer()
		defer writer.Close()
		cmd.Stderr = writer
	} else {
		return nil, errors.New("stderr logger does not adhere to log.ToWriter interface")
	}

	err = cmd.Run()
	sarifBuf := bytes.NewBufferString(sarif)
	truncateBuffers(6*1024, sarifBuf) // limit to 6KB
	appctx.Stats(ctx).DistributionMs("cocofix_runner.call", stats.Tags{
		"error":       strconv.FormatBool(err != nil),
		"integration": integration.String(),
	}, time.Since(start))

	if err != nil {
		appctx.Logger(ctx).Named("dependabot_runner").Error("Got error from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("sarifInput", sarifBuf.String()),
			kvp.String("integration", integration.String()),
		)

		if cmd.ProcessState.ExitCode() == 255 {
			// we should retry if process failed with 255 exit code
			return nil, &TransientError{
				Err: err,
			}
		}
		return nil, &NonRetriableError{errors.Wrap(err, "Got error from cocofix")}
	}

	// 5. post process cocofix output
	dat, err := os.ReadFile(of)
	if err != nil {
		appctx.Logger(ctx).Named("dependabot_runner").Error("Failed to read output file from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("sarifInput", sarifBuf.String()),
			kvp.String("integration", integration.String()),
		)
		return nil, &NonRetriableError{errors.Wrap(err, "Failed to read output file from cocofix")}
	}

	resp, err := parseResponseJson(dat)
	if err != nil {
		appctx.Logger(ctx).Named("dependabot_runner").Error("Failed to parse json output from cocofix",
			kvp.String("scriptPath", cmd.Path),
			kvp.Strings("scriptArgs", cmd.Args),
			kvp.String("error", err.Error()),
			kvp.String("response", sanitizeJsonString(string(dat))),
			kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
			kvp.String("sarifInput", sarifBuf.String()),
		)
		return nil, &NonRetriableError{errors.Wrap(err, "Failed to parse json output from cocofix")}
	}

	appctx.Logger(ctx).Named("dependabot_runner").Info("cocofix ran with success.",
		kvp.String("scriptPath", cmd.Path),
		kvp.Strings("scriptArgs", cmd.Args),
		kvp.String("response", sanitizeJsonString(string(dat))),
		kvp.Int("exitCode", cmd.ProcessState.ExitCode()),
	)

	return resp, nil
}

func (c *CocofixRunner) setupInputSrcForDependabot(
	ctx context.Context,
	dir string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	filePaths []string) (string, error) {

	srcInputDir := filepath.Join(dir, "src")
	err := os.Mkdir(srcInputDir, 0700)
	if err != nil {
		return "", &TransientError{Err: errors.Wrap(err, "error creating the src directory")}
	}

	files := make([]string, len(filePaths))
	copy(files, filePaths)
	configFiles := FindConfigurationFiles(files)
	files = append(files, configFiles...)

	for _, f := range files {
		b, err := downloadFunc(ctx, f)
		if err != nil {
			// Configuration files are optional. If a configuration file is not found, we can still continue
			if IsConfigurationFile(f) {
				appctx.Logger(ctx).Named("dependabot_runner").WithError(err).Info("error downloading a configuration file from spokes. Skipping it", repoID.AsKVP(), kvp.String("file", f))
				continue
			}

			if errors.Is(err, spokes.ErrFileNotFound) {
				return "", &NonRetriableError{Err: errors.Wrap(err, "error downloading file")}
			}
			appctx.Logger(ctx).Named("dependabot_runner").WithError(err).Info("error downloading a file from spokes", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error downloading file")}
		}

		// sanitize file path if not a configuration file
		destFp, err := sanitizeFilePath(srcInputDir, filepath.Join(srcInputDir, f))
		if err != nil {
			appctx.Logger(ctx).Named("dependabot_runner").Info("error sanitizing input file path", kvp.Err(err), kvp.String("file", f))
			return "", &NonRetriableError{Err: errors.Wrap(err, "error sanitizing input file path")}
		}

		err = os.MkdirAll(filepath.Dir(destFp), 0700)
		if err != nil {
			appctx.Logger(ctx).Named("dependabot_runner").WithError(err).Info("error creating the directory", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error creating the directory")}
		}

		err = os.WriteFile(destFp, b, 0644)
		if err != nil {
			appctx.Logger(ctx).Named("dependabot_runner").WithError(err).Info("error writing the file", repoID.AsKVP(), kvp.String("file", f))
			return "", &TransientError{Err: errors.Wrap(err, "error writing the file")}
		}
		c.filesums[f] = ts.BuildFileChecksum(b)
	}

	return srcInputDir, nil
}

func (c *CocofixRunner) setupInputsForDependabot(
	ctx context.Context,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	sarif string,
	filePaths []string) (string, string, string, error) {
	defer c.emitDistribution(ctx, "setupInputsForDependabot")()
	dir, err := os.MkdirTemp("", "autofix")
	if err != nil {
		return "", "", "", &TransientError{Err: errors.Wrap(err, "error creating the cocofix inputs directory")}
	}

	// Input source code
	var srcInputDir string
	if len(filePaths) > 0 {
		srcInputDir, err = c.setupInputSrcForDependabot(ctx, dir, downloadFunc, repoID, filePaths)
		if err != nil {
			return dir, "", "", err
		}
	}

	// Input sarif file, no need to sanitize as sarif file is provided by dependabot
	sarifPath := filepath.Join(dir, "input.sarif")
	err = os.WriteFile(sarifPath, []byte(sarif), 0600)
	if err != nil {
		return dir, "", "", &TransientError{Err: errors.Wrap(err, "error while writing the sarif file")}
	}

	return dir, sarifPath, srcInputDir, nil
}
