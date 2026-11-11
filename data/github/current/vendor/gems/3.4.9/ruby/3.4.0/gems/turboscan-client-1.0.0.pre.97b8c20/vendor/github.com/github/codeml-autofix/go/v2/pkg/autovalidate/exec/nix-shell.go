package exec

import (
	"bytes"
	"context"
	_ "embed"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/github/codeml-autofix/go/v2/pkg/autofix/enhancedctx"
	"github.com/github/github-telemetry-go/kvp"
)

// NixShellEnv provides a command environment backed by a temporary nix-shell workspace.
type NixShellEnv struct {
	workingDir             string
	userSuppliedWorkingDir bool
}

// NewNixShellEnv constructs a new nix-shell environment.
func NewNixShellEnv() *NixShellEnv { return &NixShellEnv{} }

// SetWorkingDir implements CommandEnvironment to allow injecting a workspace.
func (e *NixShellEnv) SetWorkingDir(dir string) {
	e.workingDir = dir
	e.userSuppliedWorkingDir = true
}

const nixShellFileName = "shell.nix"

//go:embed shell.nix
var nixShellContent string

// NixShellCommandBuilder implements CommandBuilder for a nix-shell workspace.
type NixShellCommandBuilder struct {
	ctx                    context.Context
	workingDir             string
	userSuppliedWorkingDir bool
	outputFiles            map[string]string // logical -> absolute path
}

// Init sets up the nix-shell workspace and materializes the provided FileMapping.
func (e *NixShellEnv) Init(ctx context.Context, fm FileMapping) (CommandBuilder, error) {
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
		workingDir, err = os.MkdirTemp("", "nix-shell-workspace-")
		if err != nil {
			return nil, fmt.Errorf("create temp workspace: %w", err)
		}
	}

	// Always attempt cleanup on error via helper
	cleanupOnErr := func(b *NixShellCommandBuilder, wrap error) (CommandBuilder, error) {
		if b != nil {
			_ = b.Cleanup()
		}
		return nil, wrap
	}

	builder := &NixShellCommandBuilder{
		ctx:                    ctx,
		workingDir:             workingDir,
		userSuppliedWorkingDir: e.userSuppliedWorkingDir,
		outputFiles:            map[string]string{},
	}

	if err := os.WriteFile(filepath.Join(workingDir, nixShellFileName), []byte(nixShellContent), 0o644); err != nil { //nolint:gosec // allow file permission 0644
		return cleanupOnErr(builder, fmt.Errorf("write %s: %w", nixShellFileName, err))
	}

	// Materialize FileMapping (skip rewriting existing inputs for user-supplied workingDir)
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
				if err := writeBytesInput(workingDir, logical, s.data); err != nil {
					return cleanupOnErr(builder, fmt.Errorf("materialize bytes %q: %w", logical, err))
				}
			}
			if s.direction.IsOutput() {
				builder.outputFiles[logical] = abs
			}
		case HostPathSpec:
			if s.direction.IsInput() && !exists {
				if err := copyHostPathInto(workingDir, logical, s.hostPath); err != nil {
					return cleanupOnErr(builder, fmt.Errorf("copy host path %q -> %q: %w", s.hostPath, logical, err))
				}
			}
			if s.direction.IsOutput() {
				builder.outputFiles[logical] = abs
			}
		case OutputSpec:
			if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
				return cleanupOnErr(builder, fmt.Errorf("prepare output path %q: %w", logical, err))
			}
			builder.outputFiles[logical] = abs
		default:
			return cleanupOnErr(builder, fmt.Errorf("unsupported FileMappingSpec type %T for %q", spec, logical))
		}
	}

	return builder, nil
}

// Cleanup removes the temporary workspace.
func (b *NixShellCommandBuilder) Cleanup() error {
	if b.workingDir == "" {
		return nil
	}

	if b.userSuppliedWorkingDir {
		// Keep user-supplied workspace, just remove generated shell.nix
		return os.Remove(filepath.Join(b.workingDir, nixShellFileName))
	}

	return os.RemoveAll(b.workingDir)
}

// GetOutputFile returns the content of an output logical file.
func (b *NixShellCommandBuilder) GetOutputFile(fileName string) ([]byte, error) {
	path, ok := b.outputFiles[fileName]
	if !ok {
		return nil, fmt.Errorf("output file %q not registered", fileName)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read output file %q: %w", fileName, err)
	}
	return data, nil
}

// NewCommand creates a new command executed inside nix-shell.
func (b *NixShellCommandBuilder) NewCommand(name string, arg ...string) Command {
	parts := append([]string{name}, arg...)

	// Special-case a /bin/sh -c invocation: the third element is a script that
	// we should quote as a single shell word while leaving the leading pieces
	// untouched.
	var runStr string
	if len(parts) >= 3 && parts[0] == "/bin/sh" && parts[1] == "-c" {
		// The script (parts[2]) may already contain redirections / quotes; wrap it
		// in single quotes unless it already contains newlines that would benefit
		// from here-doc usage (not expected for our current validators).
		script := parts[2]
		runStr = parts[0] + " " + parts[1] + " " + shQuote(script)
		if len(parts) > 3 { // Append any remaining arguments after the script (rare)
			for _, a := range parts[3:] {
				runStr += " " + shQuote(a)
			}
		}
	} else {
		// Generic case: quote each argument as needed so the resulting single
		// string reproduces the original argv when parsed by /bin/sh.
		quoted := make([]string, 0, len(parts))
		for _, p := range parts {
			quoted = append(quoted, shQuote(p))
		}
		runStr = strings.Join(quoted, " ")
	}

	cmd := exec.Command("nix-shell", nixShellFileName, "--run", runStr)
	cmd.Dir = b.workingDir
	wrapped := &NixShellCmd{cmd: cmd}
	logger := enhancedctx.Logger(b.ctx)
	logger.Debug("New command", kvp.String("command", wrapped.String()), kvp.String("exec-env", "nix-shell"), kvp.String("cwd", b.workingDir), kvp.String("run-str", runStr))
	return wrapped
}

// NixShellCmd wraps exec.Cmd to satisfy Command.
type NixShellCmd struct{ cmd *exec.Cmd }

// CombinedOutput runs the command and returns its combined standard output and standard error.
func (c *NixShellCmd) CombinedOutput() ([]byte, error) { return c.cmd.CombinedOutput() }

// Output runs the command and returns its standard output.
func (c *NixShellCmd) Output() ([]byte, error) { return c.cmd.Output() }

// Run starts the specified command and waits for it to complete.
func (c *NixShellCmd) Run() error { return c.cmd.Run() }

// Start starts the specified command but does not wait for it to complete.
func (c *NixShellCmd) Start() error { return c.cmd.Start() }

// Wait waits for the command to exit and waits for any copying to stdin or copying from stdout or stderr to complete.
func (c *NixShellCmd) Wait() error { return c.cmd.Wait() }

// StdinPipe returns a pipe that will be connected to the command's standard input when the command starts.
func (c *NixShellCmd) StdinPipe() (io.WriteCloser, error) { return c.cmd.StdinPipe() }

// StdoutPipe returns a pipe that will be connected to the command's standard output when the command starts.
func (c *NixShellCmd) StdoutPipe() (io.ReadCloser, error) { return c.cmd.StdoutPipe() }

// StderrPipe returns a pipe that will be connected to the command's standard error when the command starts.
func (c *NixShellCmd) StderrPipe() (io.ReadCloser, error) { return c.cmd.StderrPipe() }
func (c *NixShellCmd) String() string                     { return c.cmd.String() }

// Environ returns a copy of the environment in which the command would be run.
func (c *NixShellCmd) Environ() []string { return c.cmd.Env }

// Helper to write bytes input
func writeBytesInput(root, logical string, data []byte) error {
	full := filepath.Join(root, logical)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		return err
	}
	return os.WriteFile(full, data, 0o644) //nolint:gosec // allow file permission 0644
}

// copyHostPathInto copies a file or directory to the logical location in workspace.
func copyHostPathInto(root, logical, hostPath string) error {
	info, err := os.Stat(hostPath)
	if err != nil {
		return err
	}
	dest := filepath.Join(root, logical)
	if info.IsDir() {
		return copyDir(hostPath, dest)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	data, err := os.ReadFile(hostPath)
	if err != nil {
		return err
	}
	return os.WriteFile(dest, data, info.Mode()&0o777)
}

// copyDir recursively copies a directory tree.
func copyDir(src, dest string) error {
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

// Shell quoting helpers (POSIX compatible). We purposely keep these local to the
// nix-shell implementation to avoid premature generalisation.

var safeWordRegexp = regexp.MustCompile(`^[A-Za-z0-9_./:-]+$`)

// shQuote returns a shell-safe representation of s. If s contains only
// safe characters it is returned unchanged. Otherwise it is single-quoted
// with interior single quotes escaped via the standard POSIX pattern: '
// => '\” inside a single-quoted context.
func shQuote(s string) string {
	if s == "" {
		return "''"
	}
	if safeWordRegexp.MatchString(s) {
		return s
	}
	// Replace every single quote ' with '\''
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// HealthCheck optionally verifies nix-shell availability.
func (e *NixShellEnv) HealthCheck(ctx context.Context) error {
	_, err := exec.LookPath("nix-shell")
	if err != nil {
		return errors.New("nix-shell not found in PATH")
	}
	return nil
}

// String returns a diagnostic representation of this builder.
func (b *NixShellCommandBuilder) String() string {
	var buf bytes.Buffer
	_, _ = buf.WriteString("NixShellCommandBuilder{tempDir=")
	_, _ = buf.WriteString(b.workingDir)
	_, _ = buf.WriteString(", outputs=[")
	first := true
	for k := range b.outputFiles {
		if !first {
			_, _ = buf.WriteString(", ")
		}
		first = false
		_, _ = buf.WriteString(k)
	}
	_, _ = buf.WriteString("]}")
	return buf.String()
}
