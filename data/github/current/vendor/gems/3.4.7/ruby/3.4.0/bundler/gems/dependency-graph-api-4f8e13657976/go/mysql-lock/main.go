// The mysql-lock command runs a subcommand while holding a distributed lock.
// Run with no arguments for usage.
package main

/*

IMPLEMENTATION

The locks table holds triples (name, holder, expires) where
- name is the name of the lock,
- holder uniquely identifies a mysql-lock process, and
- expiry is the time at which the lock expires according to the database's clock.

A lock is held if and only if expiry > now; the holder field identifies the lock holder.

We first attempt to acquire the specified lock.
This is done by (atomically) setting holder and expires, unless expires > now.
On failure, the program may fail or retry, as requested.

Once the lock is held, we start the subcommand.
Periodically, we extend our lease by (atomically) increasing expires,
as long as we remain the most recent process to hold the lock.

If we have lost the lock because our lease renewal was delayed
(perhaps because the network was temporarily slow or lossy, or the
heartbeat was scheduled late) and some other process has acquired it,
then we kill the subprocess immediately and exit.

Read http://go-database-sql.org for much good advice on Go + MySQL.

See also https://github.com/github/geyser/blob/master/adrs/0001-locking.md
for a nice overview of this problem. This program could be written as a
client of the API described in that document, calling Touch periodically
in the heartbeat loop. (Ideally the subcommand would call Touch prior to
each access of the shared state, but that requires invasive changes to
the subcommand program.)

*/

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/binary"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"golang.org/x/sys/unix"
)

// flags
var (
	userenv     = flag.String("user-env", "", "the environment variable containing the MySQL username")
	passwordenv = flag.String("password-env", "", "the environment variable containing the MySQL username")
	host        = flag.String("host", "", "the MySQL server host name")
	port        = flag.Int("port", 3306, "the MySQL server port")
	lock        = flag.String("lock", "", "the lock name")
	wait        = flag.Bool("wait", true, "wait and retry if lock is not initially available")
	dir         = flag.String("dir", "", "directory in which to run subcommand")
)

const (
	ExitSubcommandError = 10 // subcommand terminated unsuccessfully
	ExitLockUnavailable = 11 // lock unavailable
	ExitPreempted       = 12 // lock preempted by another process
)

var start = time.Now().UTC()

const debug = false

func main() {
	log.SetPrefix("mysql-lock: ")
	if debug {
		log.SetPrefix(fmt.Sprintf("mysql-lock(%d): ", os.Getpid()))
	}
	log.SetFlags(0)
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, `Usage: mysql-lock [flags] database table executable [args ...]

The mysql-lock command runs a subcommand (in a similar manner to the env,
time, and strace commands) while holding a distributed lock, implemented
by a row in the named MySQL database table.
The lock name is specified by the -lock flag; its default value is "".
If the lock is not available, mysql-lock prints a message, then,
depending on the -wait flag (default: true),
either waits until the lock becomes available, or exits.
When the subcommand terminates, the lock is released.

There is no broadcast when a lock is released, so other clients may wait up
to one poll period before they wake up.

If the process should lose the lock during subcommand execution (because
the server missed consecutive periodic heartbeats due to network latency
or scheduling delay), mysql-lock prints an error, kills the subprocess,
and terminates.

Any failure to interact with the database causes this program to be
killed. And any failure of this program while the subprocess is
running causes the subprocess to be killed. Therefore this command
should only be used to run a subcommand that is critically dependent
on the database. For other subcommands, consider using locks based on
Redis, Consul, or ZooKeeper.

The program uses the following exit codes in special cases:

 10 - Subcommand terminated unsuccessfully. The cause is printed to stderr.
 11 - Lock unavailable (-wait=false).
 12 - Lock preempted by another process.

Flags:
`)
		flag.PrintDefaults()
	}
	flag.Parse()
	if flag.NArg() < 3 {
		flag.Usage()
		os.Exit(1)
	}
	database := flag.Args()[0]
	table := flag.Args()[1]
	if strings.Contains(table, "`") {
		log.Fatalf("invalid table name: %q", table)
	}
	if len(*lock) > 255 {
		log.Fatalf("-lock name too long")
	}

	if len(*userenv) == 0 {
		log.Fatalf("No -user-env value supplied")
	}

	user := os.Getenv(*userenv)

	if len(user) == 0 {
		log.Fatalf(fmt.Sprintf("No database username found in %s", *userenv))
	}

	if len(*passwordenv) == 0 {
		log.Fatalf("No -password-env value supplied")
	}

	password := os.Getenv(*passwordenv)

	if len(password) == 0 {
		log.Fatalf(fmt.Sprintf("No database password found in %s", *passwordenv))
	}

	// Connect to MySQL.
	db, err := sql.Open("mysql", fmt.Sprintf("%s:%s@tcp(%s:%d)/%s", user, password, *host, *port, database))
	if err != nil {
		log.Fatalf("sql open: %v", err) // e.g. access denied, invalid hostname
	}

	// id is a human-readable string that uniquely identifies
	// every mysql-lock process instance.  It comprises the node
	// name (typically a k8s pod name), the process id, the
	// process start time in microseconds since UNIX epoch, plus
	// 32 strongly random bits for uniqueness in the improbable
	// event that the other three components are equal.
	id := fmt.Sprintf("%s:%d@%d-%08x", nodename(), os.Getpid(), start.UnixNano()/1000, rand32())

	// heartbeat is the client-side poll period for server state changes.
	// It is a fraction of the lease duration
	// so that a single missed heartbeat is not a problem.
	const (
		heartbeat = 15 * time.Second
		lease     = 1 * time.Minute
	)

	// Create table.
	//
	// This is for the benefit of tests. In production, the table
	// must exist already because GitHub production role accounts
	// don't have CREATE TABLE capability, so you must first go
	// through the Skeefree schema migration process.
	info := &info{
		db:       db,
		table:    fmt.Sprintf("`%s`", table),
		lockname: *lock,
		id:       id,
		lease:    lease,
	}
	if err := create(info); err != nil {
		log.Fatalf("create: %v", err)
	}

	// Acquire initial lock.
	holder := acquire(info)
	if holder != id {
		if !*wait {
			log.Printf("lock %q held by %q", info.lockname, holder)
			os.Exit(ExitLockUnavailable)
		}

		// Poll until available.
		log.Printf("lock %q held by %q...", info.lockname, holder)
		prev := holder
		for {
			time.Sleep(heartbeat)
			holder = acquire(info)
			if holder == id {
				break
			}
			if holder != prev {
				log.Printf("lock %q now held by %q...", info.lockname, holder)
				prev = holder
			}
		}
	}
	log.Printf("lock %q acquired by %q", info.lockname, id)

	// Start the subcommand.
	cmd := exec.Command(flag.Args()[2], flag.Args()[3:]...)
	cmd.Dir = *dir
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	// Ensure that if this process dies, so does the subcommand,
	// otherwise it may outlive the lock (Linux only).
	setPdeathsig(cmd)
	if err := cmd.Start(); err != nil {
		log.Fatalf("exec: %v", err)
	}

	// Start the heartbeat.
	go func() {
		for {
			time.Sleep(heartbeat)
			holder := extend(info)
			if holder != id {
				// Lock expired and was claimed by another.
				log.Printf("lock %q lost to %q!", info.lockname, holder)
				cmd.Process.Kill()
				os.Exit(ExitPreempted)
			}
		}
	}()

	// Wait for completion of subcommand.
	err = cmd.Wait()
	// Release the lock so that subsequent runs needn't wait for the lease to expire.
	// This is merely an optimization.
	release(info)
	if err != nil {
		// Log the termination status of the subcommand, if it failed.
		// We do not exit with the same exit code as this would make it impossible
		// to distinguish mysql-lock errors from those of the subcommand.
		log.Printf("subcommand terminated by %v", cmd.ProcessState)
		os.Exit(ExitSubcommandError)
	}
}

// nodename returns the name by which this system is known in its
// local network namespace (e.g. k8s container, /etc/hosts, or DNS).
func nodename() string {
	var uts unix.Utsname
	if err := unix.Uname(&uts); err != nil {
		log.Fatalf("uname: %v", err)
	}
	name := uts.Nodename[:]
	if i := bytes.IndexByte(name, 0); i >= 0 {
		name = name[:i]
	}
	return string(name)
}

// rand32 returns a 32 random bits from a secure generator.
func rand32() uint32 {
	var random [4]byte
	if _, err := rand.Read(random[:]); err != nil {
		log.Fatalf("random read: %v", err)
	}
	return binary.LittleEndian.Uint32(random[:])
}

// --- database operations ---

// Information needed by database operations.
type info struct {
	db       *sql.DB
	table    string        // table name, SQL-quoted
	lockname string        // name of the lock (row)
	id       string        // globally unique identifier of this process
	lease    time.Duration // lease duration
}

// MySQL errors. See https://dev.mysql.com/doc/mysql-errors/5.7/en/server-error-reference.html
const (
	mysqlNoSuchTableError    = 1146
	mysqlDuplicateEntryError = 1062
)

func isMySQLError(err error, code uint16) bool {
	myErr, ok := err.(*mysql.MySQLError)
	return ok && myErr.Number == code
}

// create attempts to create the table of locks.
func create(info *info) error {
	// Check explicitly whether table exists:
	// Unfortunately CREATE TABLE IF NOT EXISTS fails if the user doesn't
	// have CREATE TABLE permission, even if the table exists.
	if _, err := info.db.Exec(`describe ` + info.table); !isMySQLError(err, mysqlNoSuchTableError) {
		return err // success (table exists) or other error (e.g no such host)
	}
	// No such table: create it.

	// We require InnoDB for its support of row-level locks.
	_, err := info.db.Exec(`create table if not exists ` + info.table + ` (lockname varchar(255) not null primary key, holder varchar(255) not null, expires datetime not null) engine=InnoDb`)
	return err
}

// acquire attempts to acquire the lock, and returns the actual holder of the lock.
func acquire(info *info) string {
	// Create an (expired) row for the lock, if none already exists.
	_, err := info.db.Exec(`insert into `+info.table+` (lockname, holder, expires) values (?, "n/a", now() - interval 1 hour)`, info.lockname)
	if err != nil {
		if !isMySQLError(err, mysqlDuplicateEntryError) {
			log.Fatalf("creating lock %q: %v", info.lockname, err)
		}
	} else if debug {
		log.Printf("dbg: created row for %s", info.lockname)
	}

	// Acquire the lock if no-one else has it.
	prev, acquired, err := transact(
		info,
		`update `+info.table+` set holder = ?, expires = now() + interval ? microsecond where lockname = ? and expires <= now()`,
		info.id,
		info.lease.Microseconds(), // see comment in 'extend'
		info.lockname)
	if err != nil {
		log.Fatalf("acquire: %v", err)
	}
	if debug {
		log.Printf("dbg: acquire %s prev=%s acquired=%t", info.lockname, prev, acquired)
	}

	if !acquired {
		return prev // held by another
	} else {
		return info.id // success
	}
}

// extend attempts to extend the lease on a lock, and returns the actual holder of the lock.
func extend(info *info) string {
	// Extend the lease if we still own it, or were the last to own it.
	//
	// There is no value that can be passed to a bare '?' that
	// expands to a SQL interval expression, and 'now() + 1'
	// yields something completely wrong; see https://github.com/golang/go/issues/46427.
	// We use 'interval ? microseconds' with a time.Duration.Microseconds,
	// because MySQL's interval syntax ignores the fractional part of a number
	// and Go's time.Duration.Seconds returns a floating point number.
	prev, renewed, err := transact(
		info,
		`update `+info.table+` set expires = now() + interval ? microsecond where lockname = ? and holder = ?`,
		info.lease.Microseconds(),
		info.lockname,
		info.id)
	if err != nil {
		log.Fatalf("acquire %s: %v", info.lockname, err)
	}
	if debug {
		log.Printf("dbg: extend %s prev=%s renewed=%t", info.lockname, prev, renewed)
	}

	if !renewed {
		return prev // lease taken by another
	} else {
		return info.id // success
	}
}

// transact performs a select/update transaction to query the
// current/previous holder and update the lock.
func transact(info *info, update string, args ...interface{}) (prev string, changed bool, err error) {
	// I tried using a single transactional compound query
	//      select ... for update;
	//      update ... where ...;
	// but was unable to avoid a server-side syntax error,
	// even with the multiStatements=true connection parameter.
	// TODO(adonovan): revisit this approach, which is much
	// more efficient due to its single round trip.

	tx, err := info.db.BeginTx(context.Background(), &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return "", false, fmt.Errorf("transact.begin: %v", err)
	}

	// Query current/previous holder.
	row := tx.QueryRow(`select holder from `+info.table+` where lockname = ? for update`, info.lockname)
	if err := row.Scan(&prev); err != nil {
		_ = tx.Rollback()
		return "", false, fmt.Errorf("transact.select: %v", err)
	}

	// Acquire/renew lock.
	res, err := tx.Exec(update, args...)
	if err != nil {
		_ = tx.Rollback()
		return "", false, fmt.Errorf("transact.update: %v", err)
	}
	nrows, _ := res.RowsAffected() // always succeeds on MySQL

	if err := tx.Commit(); err != nil {
		return "", false, fmt.Errorf("acquire.commit: %v", err)
	}
	return prev, nrows > 0, nil
}

// release releases the named lock if it is held by 'id'.
func release(info *info) {
	_, err := info.db.Exec(`update `+info.table+` set holder = "", expires = now() - interval 1 hour where lockname = ? and holder = ?`, info.lockname, info.id)
	if err != nil {
		log.Fatalf("release %s: %v", info.lockname, err)
	}
}

// setPdeathsig uses prctl(SET_PDEATHSIG) to ensure that death of this
// process for any reason causes the termination of cmd.Process. Linux only.
var setPdeathsig = func(cmd *exec.Cmd) {}
