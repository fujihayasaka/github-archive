package exec

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/github-telemetry-go/kvp"
)

// LocalEnv provides a command environment that materializes a temporary workspace
// and executes commands directly on the host using os/exec without Docker or nix-shell.
// It mirrors NixShellEnv's file mapping semantics but omits any environment provisioning.
type LocalEnv struct {
	workingDir             string
	userSuppliedWorkingDir bool
}

// NewLocalEnv constructs a new LocalEnv instance.
func NewLocalEnv() *LocalEnv { return &LocalEnv{} }

// SetWorkingDir implements CommandEnvironment.
func (e *LocalEnv) SetWorkingDir(dir string) { e.workingDir = dir; e.userSuppliedWorkingDir = true }

// LocalCommandBuilder implements CommandBuilder for a local temporary workspace.
type LocalCommandBuilder struct {
	workingDir             string
	userSuppliedWorkingDir bool
	outputFiles            map[string]string // logical -> absolute path
	workspace              string
	ctx                    context.Context
}

// Init prepares a temporary workspace and materializes the FileMapping.
func (e *LocalEnv) Init(ctx context.Context, fm FileMapping) (CommandBuilder, error) { // capture ctx for logging
	var workingDir string
	if e.workingDir != "" {
		if fi, err := os.Stat(e.workingDir); err == nil && fi.IsDir() {
			workingDir = e.workingDir
		} else if err != nil {
			return nil, fmt.Errorf("workspace path invalid: %w", err)
		} else {
			return nil, fmt.Errorf("workspace path %q is not a directory", e.workingDir)
		}
	}
	if workingDir == "" {
		var err error
		workingDir, err = os.MkdirTemp("", "local-workspace-")
		if err != nil {
			return nil, fmt.Errorf("create temp workspace: %w", err)
		}
	}

	builder := &LocalCommandBuilder{
		workingDir:             workingDir,
		userSuppliedWorkingDir: e.userSuppliedWorkingDir,
		outputFiles:            map[string]string{},
		workspace:              workingDir,
		ctx:                    ctx,
	}

	cleanupOnErr := func(wrap error) (CommandBuilder, error) {
		_ = builder.Cleanup()
		return nil, wrap
	}

	// Materialize the mapping (skip creating inputs if user-supplied workingDir already has them)
	for logical, spec := range fm {
		abs := filepath.Join(workingDir, logical)
		exists := false
		if e.userSuppliedWorkingDir {
			if _, err := os.Stat(abs); err == nil {
				exists = true
			}
		}
		switch s := spec.(type) {
		case BytesSpec:
			if s.direction.IsInput() {
				if err := localWriteBytes(workingDir, logical, s.data); err != nil {
					return cleanupOnErr(fmt.Errorf("materialize bytes %q: %w", logical, err))
				}
			}
			if s.direction.IsOutput() {
				builder.outputFiles[logical] = abs
			}
		case HostPathSpec:
			if s.direction.IsInput() && !exists {
				if err := localCopyHostPath(workingDir, logical, s.hostPath); err != nil {
					return cleanupOnErr(fmt.Errorf("copy host path %q -> %q: %w", s.hostPath, logical, err))
				}
			}
			if s.direction.IsOutput() {
				builder.outputFiles[logical] = abs
			}
		case OutputSpec:
			if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
				return cleanupOnErr(fmt.Errorf("prepare output path %q: %w", logical, err))
			}
			builder.outputFiles[logical] = abs
		default:
			return cleanupOnErr(fmt.Errorf("unsupported FileMappingSpec type %T for %q", spec, logical))
		}
	}

	return builder, nil
}

// NewCommand creates a command executed directly on the host inside the temp workspace.
func (b *LocalCommandBuilder) NewCommand(name string, arg ...string) Command {
	cmd := exec.Command(name, arg...)
	cmd.Dir = b.workspace
	wrapped := &LocalCmd{cmd: cmd}
	logger := enhancedctx.Logger(b.ctx)

	logger.Debug("New command", kvp.String("command", wrapped.String()), kvp.String("exec-env", "local"), kvp.String("cwd", b.workspace))

	return wrapped
}

// GetOutputFile retrieves bytes for an output logical file.
func (b *LocalCommandBuilder) GetOutputFile(fileName string) ([]byte, error) {
	abs, ok := b.outputFiles[fileName]
	if !ok {
		return nil, fmt.Errorf("output file %q not registered", fileName)
	}
	data, err := os.ReadFile(abs)
	if err != nil {
		return nil, fmt.Errorf("read output file %q: %w", fileName, err)
	}
	return data, nil
}

// Cleanup deletes the temporary workspace.
func (b *LocalCommandBuilder) Cleanup() error {
	if b.workingDir == "" || b.userSuppliedWorkingDir {
		return nil
	}

	return os.RemoveAll(b.workingDir)
}

// LocalCmd wraps exec.Cmd to satisfy Command.
type LocalCmd struct{ cmd *exec.Cmd }

// CombinedOutput runs the command and returns its combined standard output and standard error.
func (c *LocalCmd) CombinedOutput() ([]byte, error) { return c.cmd.CombinedOutput() }

// Output runs the command and returns its standard output.
func (c *LocalCmd) Output() ([]byte, error) { return c.cmd.Output() }

// Run starts the specified command and waits for it to complete.
func (c *LocalCmd) Run() error { return c.cmd.Run() }

// Start starts the specified command but does not wait for it to complete.
func (c *LocalCmd) Start() error { return c.cmd.Start() }

// Wait waits for the command to exit and waits for any copying to stdin or copying from stdout or stderr to complete.
func (c *LocalCmd) Wait() error { return c.cmd.Wait() }

// StdinPipe returns a pipe that will be connected to the command's standard input when the command starts.
func (c *LocalCmd) StdinPipe() (io.WriteCloser, error) { return c.cmd.StdinPipe() }

// StdoutPipe returns a pipe that will be connected to the command's standard output when the command starts.
func (c *LocalCmd) StdoutPipe() (io.ReadCloser, error) { return c.cmd.StdoutPipe() }

// StderrPipe returns a pipe that will be connected to the command's standard error when the command starts.
func (c *LocalCmd) StderrPipe() (io.ReadCloser, error) { return c.cmd.StderrPipe() }
func (c *LocalCmd) String() string                     { return c.cmd.String() }

// Environ returns a copy of the environment in which the command would be run.
func (c *LocalCmd) Environ() []string { return c.cmd.Env }

// Helpers reused with local prefix to avoid export noise.
func localWriteBytes(root, logical string, data []byte) error {
	full := filepath.Join(root, logical)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return err
	}
	return os.WriteFile(full, data, 0o644) //nolint:gosec // allow file permission 0644
}

func localCopyHostPath(root, logical, hostPath string) error {
	info, err := os.Stat(hostPath)
	if err != nil {
		return err
	}
	dest := filepath.Join(root, logical)
	if info.IsDir() {
		return localCopyDir(hostPath, dest)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	b, err := os.ReadFile(hostPath)
	if err != nil {
		return err
	}
	return os.WriteFile(dest, b, info.Mode()&0o777)
}

func localCopyDir(src, dest string) error {
	return filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, p)
		if err != nil {
			return err
		}
		target := filepath.Join(dest, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		mode := fs.FileMode(0o644)
		if info, e2 := d.Info(); e2 == nil {
			mode = info.Mode() & 0o777
		}
		return os.WriteFile(target, b, mode)
	})
}
