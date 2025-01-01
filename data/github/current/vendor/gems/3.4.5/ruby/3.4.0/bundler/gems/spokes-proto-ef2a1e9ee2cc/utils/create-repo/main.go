// Usage: script/addrepo URL
package main

import (
	"context"
	"crypto/md5"
	"database/sql"
	"flag"
	"fmt"
	"log"
	"path"
	"time"

	"github.com/go-sql-driver/mysql"
)

func main() {
	debug := flag.Bool("debug", false, "show lots of output")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Usage: script/create-repo\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	db, err := connect()
	if err != nil {
		log.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	dbCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	tx, err := db.BeginTx(dbCtx, nil)
	if err != nil {
		log.Fatal(err)
	}

	var dbe execer
	if *debug {
		dbe = &debugDB{tx}
	} else {
		dbe = tx
	}

	fileservers, err := loadFileServers(dbCtx, dbe)
	if err != nil {
		log.Fatal(err)
	}
	if len(fileservers) == 0 {
		fileservers, err = insertFileServer(dbCtx, dbe)
		if err != nil {
			log.Fatal(err)
		}
	}

	nwReplicas, err := addNetwork(dbCtx, dbe, fileservers)
	if err != nil {
		log.Fatal(err)
	}

	repoReplicas, err := addRepository(dbCtx, dbe, nwReplicas)
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("NETWORK_ID=%d\n", nwReplicas[0].NetworkID)
	fmt.Printf("REPOSITORY_ID=%d\n", repoReplicas[0].RepositoryID)
	fmt.Printf("SHARD_PATH=%s\n", shard(nwReplicas[0].NetworkID))

	if err := tx.Commit(); err != nil {
		log.Fatal(err)
	}
}

type execer interface {
	ExecContext(context.Context, string, ...interface{}) (sql.Result, error)
	QueryContext(context.Context, string, ...interface{}) (*sql.Rows, error)
}

type fileserver struct {
	Host string
}

type networkReplica struct {
	ID        int64
	NetworkID int64
	Host      string
}

type repositoryReplica struct {
	RepositoryID int64
}

func connect() (db *sql.DB, err error) {
	cfg := mysql.NewConfig()
	cfg.User = "root"
	cfg.Net = "tcp"
	cfg.Addr = "mysql"
	cfg.DBName = "github_development_spokes"
	cfg.InterpolateParams = true

	dsn := cfg.FormatDSN()

	for i := 0; i < 5; i++ {
		if i > 0 {
			time.Sleep(2 * time.Second)
			db, err = sql.Open("mysql", dsn)
			if err == nil {
				return
			}
		}
	}
	return
}

func loadFileServers(ctx context.Context, db execer) ([]fileserver, error) {
	rows, err := db.QueryContext(ctx, "SELECT host FROM fileservers")
	if err != nil {
		return nil, fmt.Errorf("loading fileservers: %w", err)
	}
	defer rows.Close()
	var res []fileserver
	for rows.Next() {
		var fs fileserver
		if err := rows.Scan(&fs.Host); err != nil {
			return nil, fmt.Errorf("error reading fileserver row %d: %w", 1+len(res), err)
		}
		res = append(res, fs)
	}
	return res, nil
}

func insertFileServer(ctx context.Context, db execer) ([]fileserver, error) {
	const (
		host = "gitrpcd"
		fqdn = "gitrpcd."
	)

	_, err := db.ExecContext(ctx, "INSERT INTO fileservers (host, fqdn, datacenter, online) "+
		"VALUES(?, ?, 'local', 1)", host, fqdn)
	if err != nil {
		return nil, fmt.Errorf("error inserting fileserver: %w", err)
	}

	return []fileserver{{Host: host}}, nil
}

func addNetwork(ctx context.Context, db execer, fileservers []fileserver) ([]networkReplica, error) {
	rows, err := db.QueryContext(ctx, "SELECT MAX(network_id) FROM network_replicas")
	if err != nil {
		return nil, fmt.Errorf("error loading max network id: %w", err)
	}
	var maxNetworkID sql.NullInt64
	if rows.Next() {
		if err := rows.Scan(&maxNetworkID); err != nil {
			rows.Close()
			return nil, fmt.Errorf("error reading network id: %w", err)
		}
	}
	rows.Close()

	res := make([]networkReplica, 0, len(fileservers))
	networkID := maxNetworkID.Int64 + 1
	for _, fs := range fileservers {
		dbRes, err := db.ExecContext(ctx, "INSERT INTO network_replicas (network_id, host, state, read_weight, created_at, updated_at) "+
			"VALUES (?, ?, 1, 100, NOW(), NOW())", networkID, fs.Host)
		if err != nil {
			return nil, fmt.Errorf("error inserting network replica %d: %w", len(res)+1, err)
		}
		id, err := dbRes.LastInsertId()
		if err != nil {
			return nil, fmt.Errorf("error getting last inserted id from network_replicas: %w", err)
		}
		res = append(res, networkReplica{ID: id, NetworkID: networkID, Host: fs.Host})
	}

	return res, nil
}

func addRepository(ctx context.Context, db execer, nwReplicas []networkReplica) ([]repositoryReplica, error) {
	rows, err := db.QueryContext(ctx, "SELECT MAX(repository_id) FROM repository_replicas")
	if err != nil {
		return nil, fmt.Errorf("error loading max repository id: %w", err)
	}
	var maxRepositoryID sql.NullInt64
	if rows.Next() {
		if err := rows.Scan(&maxRepositoryID); err != nil {
			rows.Close()
			return nil, fmt.Errorf("error reading repository id: %w", err)
		}
	}
	rows.Close()

	res := make([]repositoryReplica, 0, len(nwReplicas))
	repositoryID := maxRepositoryID.Int64 + 1
	for _, nwr := range nwReplicas {
		if _, err := db.ExecContext(ctx, "INSERT INTO repository_replicas (network_replica_id, repository_id, repository_type, host, checksum, created_at, updated_at) "+
			"VALUES (?, ?, 0, ?, 'foo', NOW(), NOW())", nwr.ID, repositoryID, nwr.Host); err != nil {
			return nil, fmt.Errorf("error inserting repository replica %d: %w", len(res)+1, err)
		}
		res = append(res, repositoryReplica{RepositoryID: repositoryID})
	}

	if _, err := db.ExecContext(ctx, "INSERT INTO repository_checksums (repository_id, repository_type, checksum, created_at, updated_at) "+
		"VALUES (?, 0, 'foo', NOW(), NOW())", repositoryID); err != nil {
		return nil, fmt.Errorf("error inserting repository_checksum: %w", err)
	}

	return res, nil
}

func shard(networkID int64) string {
	w := md5.New()
	fmt.Fprintf(w, "%d", networkID)
	hash := fmt.Sprintf("%x", w.Sum(nil))
	return path.Join(
		hash[0:1],
		"nw",
		hash[0:2],
		hash[2:4],
		hash[4:6],
		fmt.Sprintf("%d", networkID),
	)
}

type debugDB struct {
	db execer
}

func (d *debugDB) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	log.Printf("[EXEC] %s %v", query, args)
	return d.db.ExecContext(ctx, query, args...)
}

func (d *debugDB) QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error) {
	log.Printf("[QUERY] %s %v", query, args)
	return d.db.QueryContext(ctx, query, args...)
}
