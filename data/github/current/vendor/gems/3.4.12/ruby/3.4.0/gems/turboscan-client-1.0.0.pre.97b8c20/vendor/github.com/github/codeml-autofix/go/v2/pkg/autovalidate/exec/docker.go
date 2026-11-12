// Package exec provides utilities for executing commands within Docker containers.
package exec

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/github-telemetry-go/kvp"
)

// DockerEnv represents a Docker environment configuration.
// It implements the CommandEnvironment interface and holds all Docker-specific
// configuration options that will be applied when creating commands.
type DockerEnv struct {
	// Image is the Docker image to use for containers
	Image string

	// ContainerName is the optional name prefix for containers
	ContainerName string

	// Env specifies the environment variables for containers
	// Each entry is of the form "key=value"
	Env []string

	// Volumes specifies volume mounts for containers
	// Each entry is of the form "host_path:container_path" or "host_path:container_path:mode"
	Volumes []string

	// Networks specifies networks to connect containers to
	Networks []string

	// RemoveContainer specifies whether to remove containers after execution
	RemoveContainer bool

	// Interactive specifies whether to run containers in interactive mode
	Interactive bool

	// TTY specifies whether to allocate a pseudo-TTY
	TTY bool

	// User specifies the user to run commands as inside containers
	User string

	// WorkingDir specifies the working directory inside the container
	WorkingDir string

	// WaitDelay bounds the time spent waiting for commands to complete
	WaitDelay time.Duration
}

// NewDockerEnv creates a new DockerEnv with the specified image.
func NewDockerEnv(image string) *DockerEnv {
	return &DockerEnv{
		Image:           image,
		RemoveContainer: true, // Default to removing container after execution
	}
}

// SetWorkingDir implements CommandEnvironment: for Docker this sets the container working directory.
// (Note: Unlike local and nix environments where this refers to a host workspace, here it is a container path.)
func (de *DockerEnv) SetWorkingDir(dir string) { de.WorkingDir = dir }

// Init materializes files from the file mapping and returns a CommandBuilder interface.
func (de *DockerEnv) Init(ctx context.Context, fm FileMapping) (CommandBuilder, error) {
	if de.Image == "" {
		return nil, errors.New("docker environment: image must be specified")
	}

	// Always create a fresh temp directory for materialized files on the host.
	hostWorkspace, err := os.MkdirTemp("", "docker-env-")
	if err != nil {
		return nil, fmt.Errorf("failed to create temp directory: %w", err)
	}

	mounts := make(map[string]string)         // maps logical path to host path for mounting inputs
	containerPaths := make(map[string]string) // maps logical name to container path for all file mappings
	outputFiles := make(map[string]string)    // maps logical name to container path for retrieving outputs

	// Generate arbitrary workspace ID to reduce collision chances
	workspaceID := fmt.Sprintf("workspace-%d", time.Now().UnixNano())
	homeDir := "/home"
	// The container image is based on Linux, so always convert container paths to Unix style.
	containerWorkspace := filepath.ToSlash(filepath.Join(homeDir, "validator", workspaceID))

	// Process all specs from FileMapping
	for _, spec := range fm {
		logicalPath := spec.LogicalPath()
		// The container image is based on Linux, so always convert paths to Unix style.
		containerPath := filepath.ToSlash(filepath.Join(containerWorkspace, logicalPath))
		containerPaths[logicalPath] = containerPath

		// Track outputs
		if spec.Direction().IsOutput() {
			outputFiles[logicalPath] = containerPath
			// Logical paths are assumed to be in Unix style. Convert to host style for creating output dirs.
			localizedLogicalPath, localizeErr := filepath.Localize(logicalPath)
			if localizeErr != nil {
				_ = os.RemoveAll(hostWorkspace)
				return nil, fmt.Errorf("failed to localize logical %s for output with error: %w", logicalPath, localizeErr)
			}
			outputFilePath := filepath.Join(hostWorkspace, localizedLogicalPath)
			outputFileDir := filepath.Dir(outputFilePath)
			if err := os.MkdirAll(outputFileDir, 0755); err != nil {
				_ = os.RemoveAll(hostWorkspace)
				return nil, fmt.Errorf("failed creating directory for output file %s: %w", logicalPath, err)
			}
		}

		// Handle input sources via variant switch
		if spec.Direction().IsInput() {
			switch v := spec.(type) {
			case BytesSpec:
				// The logical path is assumed to be in Unix style. Convert to host style for writing.
				localizedLogicalPath, localizeErr := filepath.Localize(logicalPath)
				if localizeErr != nil {
					_ = os.RemoveAll(hostWorkspace)
					return nil, fmt.Errorf("failed to localize logical %s for input with error: %w", logicalPath, localizeErr)
				}
				hostFilePath := filepath.Join(hostWorkspace, localizedLogicalPath)
				hostFileParentDir := filepath.Dir(hostFilePath)
				if err := os.MkdirAll(hostFileParentDir, 0755); err != nil {
					_ = os.RemoveAll(hostWorkspace)
					return nil, fmt.Errorf("failed creating directory for file %s: %w", logicalPath, err)
				}
				if err := os.WriteFile(hostFilePath, v.data, 0644); err != nil { //nolint:gosec // allow file permission 0644
					_ = os.RemoveAll(hostWorkspace)
					return nil, fmt.Errorf("failed writing file %s: %w", logicalPath, err)
				}
			case HostPathSpec:
				if _, err := os.Stat(v.hostPath); err != nil {
					_ = os.RemoveAll(hostWorkspace)
					return nil, fmt.Errorf("host path %s for logical %s does not exist: %w", v.hostPath, logicalPath, err)
				}
				mounts[logicalPath] = v.hostPath
			case OutputSpec:
				// Output-only with direction Output only, no input content
			default:
				_ = os.RemoveAll(hostWorkspace)
				return nil, fmt.Errorf("unsupported FileMappingSpec implementation for %s", logicalPath)
			}
		}
	}

	// Set up volumes on the DockerEnv
	var volumes []string

	// Add temp directory as the main workspace volume
	volumes = append(volumes, hostWorkspace+":"+containerWorkspace)

	// Add host path mounts as additional volumes under the container workspace
	for logicalName, hostPath := range mounts {
		containerMountPath := containerPaths[logicalName] // Use the already computed path
		volumes = append(volumes, hostPath+":"+containerMountPath)
	}

	// Add to existing volumes
	de.Volumes = append(de.Volumes, volumes...)

	// Create the DockerCommandBuilder with this environment configuration
	builder := &DockerCommandBuilder{
		env:                de,
		ctx:                ctx,
		hostWorkspace:      hostWorkspace,
		containerWorkspace: containerWorkspace,
		mounts:             mounts,
		containerPaths:     containerPaths,
		outputFiles:        outputFiles,
	}

	return builder, nil
}

// DockerCommandBuilder implements CommandBuilder for Docker environments.
type DockerCommandBuilder struct {
	env                *DockerEnv
	ctx                context.Context
	hostWorkspace      string            // Workspace path on the host used for mapping files.
	containerWorkspace string            // Container workspace path (e.g., /home/validator/workspace-123456789)
	mounts             map[string]string // Maps logical name to host path (for mounting inputs)
	containerPaths     map[string]string // Maps logical name to container path (for all file mappings)
	outputFiles        map[string]string // Maps logical name to container path (for retrieving outputs)
}

// NewCommand creates a new DockerCmd with the specified name and arguments.
// Paths in the arguments are assumed to be Unix-style paths.
func (dcb *DockerCommandBuilder) NewCommand(name string, arg ...string) Command {
	cmd := NewDockerCmd(dcb.ctx, dcb.env, dcb.hostWorkspace)
	cmd.SetContainerPaths(dcb.containerPaths)
	cmd.SetCommand(name, arg...)
	// Log full docker command string (with substituted paths) pre-execution
	logger := enhancedctx.Logger(dcb.ctx)
	logger.Debug("New command", kvp.String("command", cmd.String()), kvp.String("exec-env", "docker"))
	return cmd
}

// GetOutputFile retrieves the content of an output file after command execution.
func (dcb *DockerCommandBuilder) GetOutputFile(logicalFilePath string) ([]byte, error) {
	_, exists := dcb.outputFiles[logicalFilePath]
	if !exists {
		return nil, fmt.Errorf("output file '%s' not found in file mapping", logicalFilePath)
	}

	// Output files are written to the container workspace, which is mounted to the host workspace.
	// So we can directly read from the host workspace directory.
	localizedLogicalPath, localizeErr := filepath.Localize(logicalFilePath)
	if localizeErr != nil {
		return nil, fmt.Errorf("failed to localize logical path %s for output file: %w", logicalFilePath, localizeErr)
	}
	hostPath := filepath.Join(dcb.hostWorkspace, localizedLogicalPath)
	data, err := os.ReadFile(hostPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read output file %s from %s: %w", logicalFilePath, hostPath, err)
	}

	return data, nil
}

// Cleanup removes the temporary directory and all its contents.
func (dcb *DockerCommandBuilder) Cleanup() error {
	if dcb.hostWorkspace != "" {
		return os.RemoveAll(dcb.hostWorkspace)
	}
	return nil
}

// WalkOutputDir walks the logical tree of output-capable paths registered in the file mapping used to initialize this builder.
// Output-capable paths are those explicitly declared as outputs. Intermediate directory nodes are synthesized.
// Order: depth-first, lexicographic sibling ordering. Returning SkipDir for a directory skips its subtree.

// Builder methods for DockerEnv

// WithVolume adds a volume to the Docker environment configuration.
func (de *DockerEnv) WithVolume(volume string) *DockerEnv {
	de.Volumes = append(de.Volumes, volume)
	return de
}

// WithNetwork adds a network to the Docker environment configuration.
func (de *DockerEnv) WithNetwork(network string) *DockerEnv {
	de.Networks = append(de.Networks, network)
	return de
}

// WithEnv adds an environment variable to the Docker environment configuration.
func (de *DockerEnv) WithEnv(env string) *DockerEnv {
	de.Env = append(de.Env, env)
	return de
}

// WithUser sets the user for the Docker environment.
func (de *DockerEnv) WithUser(user string) *DockerEnv {
	de.User = user
	return de
}

// WithWorkingDir sets the working directory for the Docker environment.
func (de *DockerEnv) WithWorkingDir(dir string) *DockerEnv {
	de.WorkingDir = dir
	return de
}

// WithContainerName sets the container name for the Docker environment.
func (de *DockerEnv) WithContainerName(name string) *DockerEnv {
	de.ContainerName = name
	return de
}

// WithRemoveContainer sets whether to remove the container after execution.
func (de *DockerEnv) WithRemoveContainer(remove bool) *DockerEnv {
	de.RemoveContainer = remove
	return de
}

// WithInteractive sets whether the Docker container runs in interactive mode.
func (de *DockerEnv) WithInteractive(interactive bool) *DockerEnv {
	de.Interactive = interactive
	return de
}

// WithTTY sets whether to allocate a pseudo-TTY for the Docker container.
func (de *DockerEnv) WithTTY(tty bool) *DockerEnv {
	de.TTY = tty
	return de
}

// DockerCmd represents a command to be run inside a Docker container.
// It implements the Command interface and is created by DockerEnv.Init().
type DockerCmd struct {
	// env holds the Docker environment configuration
	env *DockerEnv

	// ctx is the context for the command
	ctx context.Context

	// hostWorkspace is the temporary directory on the host used for materialized files (if any)
	hostWorkspace string

	// containerPaths maps logical names to container paths for path substitution
	containerPaths map[string]string

	// Path is the path of the command to run inside the container
	Path string

	// Args holds command line arguments, including the command as Args[0]
	Args []string

	// Stdin specifies the process's standard input
	Stdin io.Reader

	// Stdout and Stderr specify the process's standard output and error
	Stdout io.Writer
	Stderr io.Writer

	// cmd is the underlying docker command
	cmd *exec.Cmd

	// started indicates whether the command has been started
	started bool

	// finished indicates whether the command has finished
	finished bool

	// stdinPipe holds a reference to the stdin pipe if created
	stdinPipe *deferredPipe

	// stdoutPipe holds a reference to the stdout pipe if created
	stdoutPipe *deferredPipe

	// stderrPipe holds a reference to the stderr pipe if created
	stderrPipe *deferredPipe
}

// NewDockerCmd creates a new DockerCmd with the specified command and arguments.
// This is used internally by DockerEnv.Init().
func NewDockerCmd(ctx context.Context, env *DockerEnv, hostWorkspace string) *DockerCmd {
	return &DockerCmd{
		env:           env,
		ctx:           ctx,
		hostWorkspace: hostWorkspace,
	}
}

// SetCommand sets the command path and arguments for the DockerCmd.
func (d *DockerCmd) SetCommand(name string, arg ...string) *DockerCmd {
	d.Path = name
	d.Args = append([]string{name}, arg...)
	return d
}

// SetContainerPaths sets the container paths mapping for path substitution.
func (d *DockerCmd) SetContainerPaths(containerPaths map[string]string) *DockerCmd {
	d.containerPaths = containerPaths
	return d
}

// substituteLogicalPaths replaces logical names in command arguments with container paths.
func (d *DockerCmd) substituteLogicalPaths(args []string) []string {
	if d.containerPaths == nil {
		return args
	}

	type substitution struct {
		logicalName   string
		containerPath string
		pattern       *regexp.Regexp
	}

	substitutions := make([]substitution, 0, len(d.containerPaths))
	for logicalName, containerPath := range d.containerPaths {
		pattern := `(^|[^A-Za-z0-9_./-])(` + regexp.QuoteMeta(logicalName) + `)(($|[^A-Za-z0-9_]))`
		compiledPattern := regexp.MustCompile(pattern)
		substitutions = append(substitutions, substitution{
			logicalName:   logicalName,
			containerPath: containerPath,
			pattern:       compiledPattern,
		})
	}

	// Sort by descending logical name length to prioritize more specific (longer) logical paths.
	sort.Slice(substitutions, func(i, j int) bool { return len(substitutions[i].logicalName) > len(substitutions[j].logicalName) })

	substitutedArgs := make([]string, len(args))
	for i, arg := range args {
		substitutedArg := arg
		for _, sub := range substitutions {
			if !sub.pattern.MatchString(substitutedArg) {
				continue
			}
			substitutedArg = sub.pattern.ReplaceAllString(substitutedArg, fmt.Sprintf("${1}%s${3}", sub.containerPath))
		}
		substitutedArgs[i] = substitutedArg
	}
	return substitutedArgs
}

// buildDockerArgs constructs the docker run command arguments
func (d *DockerCmd) buildDockerArgs() []string {
	dockerCmdAndOpts := []string{"run"}

	// Add container removal flag
	if d.env.RemoveContainer {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "--rm")
	}

	// Add container name if specified
	if d.env.ContainerName != "" {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "--name", d.env.ContainerName)
	}

	// Add interactive and TTY flags
	if d.env.Interactive {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "-i")
	}
	if d.env.TTY {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "-t")
	}

	// Add user if specified
	if d.env.User != "" {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "--user", d.env.User)
	}

	// Add working directory
	workDir := d.env.WorkingDir
	if workDir != "" {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "--workdir", workDir)
	}

	// Add environment variables
	for _, env := range d.env.Env {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "-e", env)
	}

	// Add volume mounts (configured by Init method)
	for _, volume := range d.env.Volumes {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "-v", volume)
	}

	// Add networks
	for _, network := range d.env.Networks {
		dockerCmdAndOpts = append(dockerCmdAndOpts, "--network", network)
	}

	// Add the image
	if d.env.Image == "" {
		panic("DockerCmd: Image must be specified")
	}

	dockerCmdAndOpts = append(dockerCmdAndOpts, d.env.Image)

	// Add the command and its arguments with path substitution
	if len(d.Args) > 0 {
		args := d.Args
		if args[0] == "run" {
			// Avoid duplicating "run" if already present
			args = args[1:]
		}
		// Apply path substitution to convert logical names to container paths
		substitutedArgs := d.substituteLogicalPaths(args)
		dockerCmdAndOpts = append(dockerCmdAndOpts, substitutedArgs...)
	} else if d.Path != "" {
		dockerCmdAndOpts = append(dockerCmdAndOpts, d.Path)
	}

	return dockerCmdAndOpts
}

// Run starts the specified command inside a Docker container and waits for it to complete.
func (d *DockerCmd) Run() error {
	if err := d.Start(); err != nil {
		return err
	}
	return d.Wait()
}

// Start starts the specified command inside a Docker container but does not wait for it to complete.
func (d *DockerCmd) Start() error {
	if d.started {
		return errors.New("exec: already started")
	}

	dockerArgs := d.buildDockerArgs()

	var cmd *exec.Cmd
	if d.ctx != nil {
		cmd = exec.CommandContext(d.ctx, "docker", dockerArgs...)
	} else {
		cmd = exec.Command("docker", dockerArgs...)
	}

	// Set up I/O - handle deferred pipes
	if d.stdinPipe != nil {
		// Initialize the stdin pipe
		wc, err := cmd.StdinPipe()
		if err != nil {
			return err
		}
		d.stdinPipe.pipe = wc
	} else {
		cmd.Stdin = d.Stdin
	}

	if d.stdoutPipe != nil {
		// Initialize the stdout pipe
		rc, err := cmd.StdoutPipe()
		if err != nil {
			return err
		}
		d.stdoutPipe.pipe = rc
	} else {
		cmd.Stdout = d.Stdout
	}

	if d.stderrPipe != nil {
		// Initialize the stderr pipe
		rc, err := cmd.StderrPipe()
		if err != nil {
			return err
		}
		d.stderrPipe.pipe = rc
	} else {
		cmd.Stderr = d.Stderr
	}

	d.cmd = cmd
	d.started = true

	return cmd.Start()
}

// Wait waits for the command to exit and waits for any copying to stdin or copying from
// stdout or stderr to complete.
func (d *DockerCmd) Wait() error {
	if !d.started {
		return errors.New("exec: not started")
	}
	if d.finished {
		return errors.New("exec: Wait was already called")
	}

	d.finished = true

	if d.cmd == nil {
		return errors.New("exec: command not initialized")
	}

	return d.cmd.Wait()
}

// Output runs the command inside a Docker container and returns its standard output.
// Any returned error will usually be of type *ExitError.
// If c.Stderr was nil, Output populates ExitError.Stderr.
func (d *DockerCmd) Output() ([]byte, error) {
	if d.Stdout != nil {
		return nil, errors.New("exec: Stdout already set")
	}

	dockerArgs := d.buildDockerArgs()

	var cmd *exec.Cmd
	if d.ctx != nil {
		cmd = exec.CommandContext(d.ctx, "docker", dockerArgs...)
	} else {
		cmd = exec.Command("docker", dockerArgs...)
	}

	cmd.Stdin = d.Stdin
	cmd.Stderr = d.Stderr

	return cmd.Output()
}

// CombinedOutput runs the command inside a Docker container and returns its combined
// standard output and standard error.
func (d *DockerCmd) CombinedOutput() ([]byte, error) {
	if d.Stdout != nil {
		return nil, errors.New("exec: Stdout already set")
	}
	if d.Stderr != nil {
		return nil, errors.New("exec: Stderr already set")
	}

	dockerArgs := d.buildDockerArgs()

	var cmd *exec.Cmd
	if d.ctx != nil {
		cmd = exec.CommandContext(d.ctx, "docker", dockerArgs...)
	} else {
		cmd = exec.Command("docker", dockerArgs...)
	}

	cmd.Stdin = d.Stdin

	return cmd.CombinedOutput()
}

// String returns a human-readable description of the Docker command.
func (d *DockerCmd) String() string {
	dockerArgs := d.buildDockerArgs()
	dockerArgs = append([]string{"docker"}, dockerArgs...)
	return strings.Join(dockerArgs, " ")
}

// StdinPipe returns a pipe that will be connected to the command's standard input
// when the command starts inside the Docker container.
func (d *DockerCmd) StdinPipe() (io.WriteCloser, error) {
	if d.started {
		return nil, errors.New("exec: StdinPipe after process started")
	}
	if d.Stdin != nil {
		return nil, errors.New("exec: Stdin already set")
	}
	if d.stdinPipe != nil {
		return nil, errors.New("exec: StdinPipe called more than once")
	}

	// Create the deferred pipe and store a reference
	d.stdinPipe = &deferredPipe{cmd: d, pipeType: "stdin"}
	return d.stdinPipe, nil
}

// StdoutPipe returns a pipe that will be connected to the command's standard output
// when the command starts inside the Docker container.
func (d *DockerCmd) StdoutPipe() (io.ReadCloser, error) {
	if d.started {
		return nil, errors.New("exec: StdoutPipe after process started")
	}
	if d.Stdout != nil {
		return nil, errors.New("exec: Stdout already set")
	}
	if d.stdoutPipe != nil {
		return nil, errors.New("exec: StdoutPipe called more than once")
	}

	// Create the deferred pipe and store a reference
	d.stdoutPipe = &deferredPipe{cmd: d, pipeType: "stdout"}
	return d.stdoutPipe, nil
}

// StderrPipe returns a pipe that will be connected to the command's standard error
// when the command starts inside the Docker container.
func (d *DockerCmd) StderrPipe() (io.ReadCloser, error) {
	if d.started {
		return nil, errors.New("exec: StderrPipe after process started")
	}
	if d.Stderr != nil {
		return nil, errors.New("exec: Stderr already set")
	}
	if d.stderrPipe != nil {
		return nil, errors.New("exec: StderrPipe called more than once")
	}

	// Create the deferred pipe and store a reference
	d.stderrPipe = &deferredPipe{cmd: d, pipeType: "stderr"}
	return d.stderrPipe, nil
}

// Environ returns a copy of the environment variables that will be used by the command
// inside the Docker container.
func (d *DockerCmd) Environ() []string {
	env := make([]string, len(d.env.Env))
	copy(env, d.env.Env)
	return env
}

// deferredPipe implements a pipe that gets created when the Docker command starts
type deferredPipe struct {
	cmd      *DockerCmd
	pipeType string
	pipe     io.Closer
}

func (dp *deferredPipe) Read(p []byte) (n int, err error) {
	if dp.pipe == nil {
		return 0, errors.New("pipe not initialized")
	}
	if rc, ok := dp.pipe.(io.ReadCloser); ok {
		return rc.Read(p)
	}
	return 0, errors.New("pipe does not support reading")
}

func (dp *deferredPipe) Write(p []byte) (n int, err error) {
	if dp.pipe == nil {
		return 0, errors.New("pipe not initialized")
	}
	if wc, ok := dp.pipe.(io.WriteCloser); ok {
		return wc.Write(p)
	}
	return 0, errors.New("pipe does not support writing")
}

func (dp *deferredPipe) Close() error {
	if dp.pipe == nil {
		return nil
	}
	return dp.pipe.Close()
}
