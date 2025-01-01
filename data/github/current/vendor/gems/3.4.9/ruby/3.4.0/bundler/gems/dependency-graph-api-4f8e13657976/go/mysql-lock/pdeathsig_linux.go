package main

import (
	"os/exec"

	"golang.org/x/sys/unix"
)

func init() {
	setPdeathsig = func(cmd *exec.Cmd) {
		cmd.SysProcAttr = &unix.SysProcAttr{Pdeathsig: unix.SIGKILL}
	}
}
