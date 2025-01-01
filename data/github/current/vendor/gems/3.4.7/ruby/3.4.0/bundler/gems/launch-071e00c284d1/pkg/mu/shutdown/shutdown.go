// Package shutdown provides a mechanism for this process to ask a currently
// running process to shutdown, and wait for it to terminate. Use this when
// running under systemd socket activation where the restart process needs to
// wait for the current process to stop before exiting.
package shutdown

import (
	"net"
	"os"
	"syscall"
	"time"
)

// Wait sends a SIGINT to pid and listens on shutdownSock for a message
// indicating the process at pid has exited.
func Wait(pid int, shutdownSock string) error {
	if _, err := os.Stat(shutdownSock); err == nil {
		cleanupSock(shutdownSock)
	}

	l, err := net.Listen("unix", shutdownSock)
	if err != nil {
		return err
	}

	defer cleanupSock(shutdownSock)

	wait := make(chan struct{})

	if err := syscall.Kill(pid, syscall.SIGINT); err != nil {
		return err
	}

	go func() {
		for {
			fd, err := l.Accept()
			if err != nil {
				close(wait)
				return
			}
			defer fd.Close() // nolint: errcheck, gosec

			buf := make([]byte, 512)
			nr, err := fd.Read(buf)
			if err != nil {
				close(wait)
				return
			}

			if string(buf[0:nr]) == "BYE" {
				close(wait)
				return
			}
		}
	}()

	select {
	case <-wait:
	case <-time.After(time.Second * 30):
	}

	return nil
}

// Signal sends a message on shutdownSock that this process has finished
// shutting down and it is safe for the process calling Wait to exit.
func Signal(shutdownSock string) error {
	if _, err := os.Stat(shutdownSock); os.IsNotExist(err) {
		return nil
	}

	c, err := net.Dial("unix", shutdownSock)
	if err != nil {
		return err
	}

	_, err = c.Write([]byte("BYE"))
	if err != nil {
		return err
	}

	return c.Close()
}

func cleanupSock(file string) {
	_ = os.Remove(file) // nolint: gas, gosec
}
