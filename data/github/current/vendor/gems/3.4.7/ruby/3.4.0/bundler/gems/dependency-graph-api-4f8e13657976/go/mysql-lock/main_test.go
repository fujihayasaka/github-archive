// This is an integration test of the mysql-lock executable.
//
// It depends on:
// - a passwordless writable MySQL DB named 'dependency_graph_development' at root@dbhost:3306,
//   where dbhost is specified by -dbhost flag.
// - /bin/bash;
// - the Go toolchain.
//
// Run with:
//    $ go test .
// Or:
//    $ docker build .			# to test Linux behavior on a Mac
//
package main_test

import (
	"bytes"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"
)

// When debugging a failing test, enable debug=true in main.go,
// and add 'echo $PPID >&2' to shell commands,
// to display the ids of the various mysql-lock processes.

var (
	dbhost     = flag.String("dbhost", "localhost", "the MySQL server host name")
	executable = tempFileName("mysql-lock")
	tmpfile    = tempFileName("locktest") // temp file, available to subcommands as $TMPFILE
)

func TestMain(m *testing.M) {
	flag.Parse()

	// Build mysql-lock executable in temp dir.
	cmd := exec.Command("go", "build", "-o", executable)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		log.Fatal(err)
	}

	os.Exit(m.Run())
}

// tempFileName returns the name of a fresh temporary file whose stem is the given base name.
func tempFileName(base string) string {
	f, err := ioutil.TempFile("", base)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	return f.Name()
}

// The test uses knowledge of these timing constants to exercise specific scenarios.
const (
	heartbeat = 15 * time.Second
	lease     = 1 * time.Minute
)

// TestQuickRelease ensures that when running several short-lived commands in sequence,
// all run to completion in order and acquire the lock without waiting.
func TestQuickRelease(t *testing.T) {
	t0 := time.Now()
	write(t, "")
	for i := 0; i < 10; i++ {
		run(t, "quick", false, fmt.Sprintf("echo -n %d >> $TMPFILE", i))
	}
	// Assert no locking delay.
	if got, want := time.Since(t0), 5*time.Second; got >= want {
		t.Errorf("too slow: %s (want < %s)", got, want)
	}
	// Assert the correct effects were observed.
	if got, want := read(t), "0123456789"; got != want {
		t.Errorf("wrong file content: %q (want %q)", got, want)
	}
}

// TestNoWait ensures that, without -wait, exactly one of two concurrent
// commands succeeds and the other exits with code 11.
func TestNoWait(t *testing.T) {
	cmd1 := start(t, "nowait", false, "sleep 3")
	err2 := run(t, "nowait", false, "sleep 3")
	err1 := cmd1.Wait()
	// This assertion may fail spuriously if scheduling delay exceeds the sleep time.
	if (err2 != nil) == (err1 != nil) {
		t.Fatalf("wanted exactly one success: got cmd1=%v, cmd2=%v", err1, err2)
	}
	// Assert that the one that failed exited with code 11.
	if err1 == nil {
		err1, err2 = err2, err1
	}
	if got, want := err1.Error(), "exit status 11"; got != want {
		t.Errorf("wrong exit status: got %s, want %s", got, want)
	}
}

// TestPassthrough ensures that the parent's environment, pwd, and
// std{in,out,err} are passed through to the child, that the child's
// exit code is logged, and that non-zero exit of the child is logged.
func TestPassthrough(t *testing.T) {
	cmd := command("passthrough", false,
		"echo stderr >&2; read line; echo -n $(pwd) $VAR $line; exit 42")
	cmd.Stdout = new(bytes.Buffer)
	cmd.Stderr = new(bytes.Buffer)
	cmd.Dir = "/usr"
	cmd.Stdin = strings.NewReader("input")
	cmd.Env = append(cmd.Env, "VAR=123")
	err := cmd.Run()

	if got, want := err.Error(), "exit status 10"; got != want {
		t.Errorf("wrong exit status: got %s, want %s", got, want)
	}
	if got, want := fmt.Sprint(cmd.Stdout), "/usr 123 input"; got != want {
		t.Errorf("wrong stdout: got %q, want %q", got, want)
	}
	assertStderrSuffix(t, cmd, "stderr\nmysql-lock: subcommand terminated by exit status 42\n")

	// TODO(adonovan): test -dir flag.
}

// TestSignal ensures that a subcommand terminated by a signal
// causes mysql-lock to exit with code 10 and the termination state to be logged.
func TestSignal(t *testing.T) {
	cmd := command("signal", false, "kill -ILL $$")
	cmd.Stderr = new(bytes.Buffer)
	err := cmd.Run()

	if got, want := err.Error(), "exit status 10"; got != want {
		t.Errorf("wrong exit status: got %s, want %s", got, want)
	}
	// We use SIGILL because its syscall.Signal.String is the same on Linux and Mac OS.
	assertStderrSuffix(t, cmd, "mysql-lock: subcommand terminated by signal: illegal instruction\n")
}

func assertStderrSuffix(t *testing.T, cmd *exec.Cmd, wantSuffix string) {
	// Match only the suffix, to avoid benign initial messages such as "lock acquired".
	got := fmt.Sprint(cmd.Stderr)
	if !strings.HasSuffix(got, wantSuffix) {
		t.Errorf("wrong stderr: got %q, want suffix %q", got, wantSuffix)
	}
}

// TestMutualExclusion ensures that two commands under the same lock run sequentially.
// (There may be up to 1 heartbeat of delay between them.)
func TestMutualExclusion(t *testing.T) {
	write(t, "")
	cmd1 := start(t, "mutex", true, "{ echo begin; sleep 3; echo end; } >> $TMPFILE")
	run(t, "mutex", true, "{ echo begin; sleep 3; echo end; } >> $TMPFILE")
	cmd1.Wait()
	if got, want := read(t), strings.Repeat("begin\nend\n", 2); got != want {
		t.Errorf("wrong file content: %q (want %q)", got, want)
	}
}

// TestSlowSubcommand ensures that a command that runs longer than the
// lease + heartbeat period continues to hold off other contenders for the lease.
func TestSlowSubcommand(t *testing.T) {
	write(t, "")
	cmd1 := start(t, "slow", true, "{ echo begin; sleep 90; echo end; } >> $TMPFILE")
	// Allow it to acquire the lock.
	time.Sleep(3 * time.Second)
	run(t, "slow", true, "echo 2 >> $TMPFILE")
	cmd1.Wait()

	// Assert the correct effects were observed.
	if got, want := read(t), "begin\nend\n2\n"; got != want {
		t.Errorf("wrong file content: %q (want %q)", got, want)
	}
}

// TestLockIndependence ensures that two commands under different locks run concurrently.
func TestLockIndependence(t *testing.T) {
	// Choose a fresh lock name here so previous tests don't delay acquisition.
	write(t, "")
	cmd1 := start(t, "lock1", true, "{ echo begin; sleep 3; echo end; } >> $TMPFILE")
	run(t, "lock2", true, "{ echo begin; sleep 3; echo end; } >> $TMPFILE")
	cmd1.Wait()
	// This assertion is somewhat timing-sensitive and may fail spuriously
	// if one command is started 3s late.
	if got, want := read(t), "begin\nbegin\nend\nend\n"; got != want {
		t.Errorf("wrong file content: %q (want %q)", got, want)
	}
}

// TestWakeupDelay ensures that several short-lived commands issued concurrently
// all run to completion, sequentially, with no more than one hearbeat of delay.
func TestWakeupDelay(t *testing.T) {
	write(t, "")
	t0 := time.Now()
	const N = 4
	var cmds [N]*exec.Cmd
	for i := range cmds {
		cmds[i] = start(t, "wakeup-delay", true,
			"{ echo begin; sleep 3; echo end; } >> $TMPFILE")
	}
	for _, cmd := range cmds {
		cmd.Wait()
	}

	// Assert at most 1 heartbeat of delay between each 3s subcommand.
	// This assertion is somewhat timing-sensitive and may fail
	// spuriously if there is a large scheduling delay.
	if got, want := time.Since(t0), N*3*time.Second+(N-1)*heartbeat; got >= want {
		t.Errorf("too slow: %s (want < %s)", got, want)
	}
	// Assert commands ran in sequence.
	if got, want := read(t), strings.Repeat("begin\nend\n", N); got != want {
		t.Errorf("wrong file content: %q (want %q)", got, want)
	}
}

// TestLockDeath tests that death of the lock-holding process causes
// death of the subcommand.  This property holds only on Linux.
func TestLockDeath(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("prctl(SET_PDEATHSIG) not supported; skipping.")
	}
	err := run(t, "lock-death", true,
		"{ echo begin; kill -9 $PPID; sleep 1; echo end; } > $TMPFILE 2>&1")
	if err == nil || err.Error() != "signal: killed" {
		t.Errorf("lock process was not killed: Wait returned %v", err)
	}
	// Wait for subcommand to expire naturally if it was not killed.
	time.Sleep(2 * time.Second)
	if got, want := read(t), "begin\n"; got != want {
		t.Errorf("subcommand output was %q, want %q", got, want)
	}
}

// TestMissedHeartbeat tests that failure to send two heartbeats
// does not result in loss of the lock.
// This test is slow to reduce its timing-sensitivity.
func TestMissedHeartbeat(t *testing.T) {
	write(t, "")
	cmd1 := start(t, "missed-heartbeat", true,
		"{ echo begin 1; sleep 45; echo end 1; } >> $TMPFILE")
	// Allow it to acquire the lock.
	time.Sleep(3 * time.Second)
	cmd2 := start(t, "missed-heartbeat", true, "echo 2 >> $TMPFILE")

	// Suspend lock holder's heartbeat.
	cmd1.Process.Signal(syscall.SIGSTOP)

	// Wait for it to miss two beats.
	time.Sleep(2 * heartbeat)

	// Resume heartbeat.
	cmd1.Process.Signal(syscall.SIGCONT)

	// Observe that it was not preempted.
	cmd1.Wait()
	cmd2.Wait()
	if got, want := read(t), "begin 1\nend 1\n2\n"; got != want {
		t.Errorf("output was %q, want %q", got, want)
	}
}

// TestLeaseTimeout tests that failure to send heartbeats for the
// duration of the lease causes loss of the lock and termination of the subcommand.
// This test is slow to reduce its timing-sensitivity.
func TestLeaseTimeout(t *testing.T) {
	write(t, "")
	cmd1 := start(t, "timeout", true, "{ echo begin 1; sleep 100; echo end 1; } >> $TMPFILE")
	// Allow cmd1 to acquire the lock.
	time.Sleep(3 * time.Second)
	cmd2 := start(t, "timeout", true, "echo 2 >> $TMPFILE")

	// Suspend lock holder's heartbeat.
	cmd1.Process.Signal(syscall.SIGSTOP)

	// Wait for lease to expire.
	time.Sleep(lease)

	// Wait another poll interval so cmd2 wakes up and preempts the lock.
	time.Sleep(heartbeat)

	// Resume cmd1 heartbeat.
	cmd1.Process.Signal(syscall.SIGCONT)

	// Assert that cmd1 was preempted (exit code 12).
	if got, want := fmt.Sprint(cmd1.Wait()), "exit status 12"; got != want {
		t.Errorf("cmd1 had wrong exit: got %q, want %q", got, want)
	}
	// Assert that cmd2 succeeded.
	if err := cmd2.Wait(); err != nil {
		t.Errorf("cmd2 failed: %v", err)
	}
	// Assert that effects of cmd1 were interrupted by cmd2.
	if got, want := read(t), "begin 1\n2\n"; got != want {
		t.Errorf("output was %q, want %q", got, want)
	}

	// TODO(adonovan):
	// - The log prints `lock lost to ""`. Find out why.
	// - Assert  that cmd1 subcommand was actually terminated (not still sleeping).
	// - Add a variant in which cmd1 never wakes up.
}

// ---- helpers ----

// run runs a lock command to completion and returns its Wait result.
func run(t *testing.T, lock string, wait bool, shellcmd string) error {
	return start(t, lock, wait, shellcmd).Wait()
}

// start starts a lock command and returns its Cmd.
func start(t *testing.T, lock string, wait bool, shellcmd string) *exec.Cmd {
	cmd := command(lock, wait, shellcmd)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	return cmd
}

// command constructs a lock-guarded shell command.
func command(lock string, wait bool, shellcmd string) *exec.Cmd {
	cmd := exec.Command(executable, append([]string{
		"-lock=" + lock,
		fmt.Sprintf("-wait=%t", wait),
		"-host=" + *dbhost,
		"dependency_graph_development", // database
		"test_locks",                   // table
	}, "/bin/bash", "-c", shellcmd)...)
	cmd.Env = append(os.Environ(), "TMPFILE="+tmpfile)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	return cmd
}

// write writes the string to the temp file.
func write(t *testing.T, content string) {
	if err := ioutil.WriteFile(tmpfile, []byte(content), 0666); err != nil {
		t.Fatal(err)
	}
}

// read reads the contents of the temp file.
func read(t *testing.T) string {
	data, err := ioutil.ReadFile(tmpfile)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}
