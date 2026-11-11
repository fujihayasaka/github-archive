//go:build linux

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"golang.org/x/sys/unix"
)

const childFlag = "--child"

func main() {
	args := os.Args[1:]
	if len(args) > 0 && args[0] == childFlag {
		if os.Getpid() != 1 {
			fmt.Fprintln(os.Stderr, "pid-ns-exec: internal child mode may only run as PID 1")
			os.Exit(1)
		}
		os.Exit(runChild(args[1:]))
	}
	os.Exit(runParent(args))
}

func runParent(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: pid-ns-exec <command> [args...]")
		return 1
	}

	childArgs := append([]string{childFlag}, args...)
	cmd := exec.Command(os.Args[0], childArgs...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags: syscall.CLONE_NEWPID | syscall.CLONE_NEWNS,
	}

	err := cmd.Run()
	if err == nil {
		return 0
	}

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}

	fmt.Fprintf(os.Stderr, "pid-ns-exec: spawn: %v\n", err)
	return 1
}

func runChild(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: pid-ns-exec <command> [args...]")
		return 1
	}

	if err := unix.Mount("none", "/", "", uintptr(unix.MS_REC|unix.MS_PRIVATE), ""); err != nil {
		fmt.Fprintf(os.Stderr, "pid-ns-exec: mount private /: %v\n", err)
		return 1
	}
	if err := unix.Mount("proc", "/proc", "proc", 0, ""); err != nil {
		fmt.Fprintf(os.Stderr, "pid-ns-exec: mount /proc: %v\n", err)
		return 1
	}
	if err := dropCapabilities(); err != nil {
		fmt.Fprintf(os.Stderr, "pid-ns-exec: drop capabilities: %v\n", err)
		return 1
	}

	binary, err := exec.LookPath(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "pid-ns-exec: look path %q: %v\n", args[0], err)
		return 1
	}
	if err := unix.Exec(binary, args, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "pid-ns-exec: exec %q: %v\n", binary, err)
		return 1
	}
	return 0
}

func dropCapabilities() error {
	header := &unix.CapUserHeader{
		Version: unix.LINUX_CAPABILITY_VERSION_3,
		Pid:     0,
	}
	data := [2]unix.CapUserData{}
	if err := unix.Capset(header, &data[0]); err != nil {
		return err
	}
	if err := unix.Prctl(unix.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0); err != nil {
		return err
	}
	return nil
}
