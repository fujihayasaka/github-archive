package main

/*
   Simple script to create a periodic read or write load against a local
   instance of TMA. If run with default parameters, it will execute a
   single transaction only, to perform periodic requests, set the period
   attribute to the desired period in milliseconds.
*/

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"reflect"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/stretchr/testify/require"
)

func newTransactionalDatabaseWithoutTruncate(t *testing.T) (*mysql.LiveDatabase, *sql.Tx) {
	db, err := sql.Open("mysql", "tma:TMAdevP4ssw0rd!@tcp(127.0.0.1:3337)/tma_dev?parseTime=true")
	require.NoError(t, err)
	tx, err := db.BeginTx(context.Background(), nil)
	require.NoError(t, err)
	return mysql.NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter), tx
}

func main() {
	var methodFile = flag.String("test-method-file", "test-methods.jsonl", "file containing list of methods to test")
	var methodRunCount = flag.Int("method-run-count", 50, "number of times to run each method")
	flag.Parse()

	if *methodFile == "" {
		panic("test-method-file must be defined")
	}

	methods, err := readMethodsFromFile(*methodFile)
	if err != nil {
		panic(err)
	}

	for _, method := range methods {
		if err := callMethodByName(*methodRunCount, method.MethodName, method.Identifiers); err != nil {
			panic(err)
		}
	}
}

type MethodTest struct {
	MethodName  string                        `json:"methodName"`
	Identifiers attestation.IdentifiersGitHub `json:"identifiers"`
}

/*
Expected file content:
{"methodName": "Method1", "identifiers": {"DomainID": 1, "OwnerID": 123, "SubjectDigests": ["sha256:12345678"]}}
{"methodName": "Method2", "identifiers": {"DomainID": 2, "OwnerID": 456, "SubjectDigests": ["sha256:12345678"]}}
*/

func readMethodsFromFile(filename string) ([]MethodTest, error) {
	fileContent, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var methods []MethodTest

	decoder := json.NewDecoder(bytes.NewReader(fileContent))

	for decoder.More() {
		var method MethodTest
		if err := decoder.Decode(&method); err != nil {
			return nil, err
		}
		methods = append(methods, method)
	}
	return methods, nil
}

func callMethodByName(methodRunCount int, methodName string, identifiers attestation.IdentifiersGitHub) error {
	totalElapsed := time.Duration(0)

	for i := range methodRunCount {
		db, _ := newTransactionalDatabaseWithoutTruncate(&testing.T{})

		// Get the value of the object
		v := reflect.ValueOf(db)

		// Get the method by name
		method := v.MethodByName(methodName)
		if !method.IsValid() {
			return fmt.Errorf("method %s not found", methodName)
		}

		args := []reflect.Value{
			// First argument: context.Context
			reflect.ValueOf(context.Background()),
			// Second argument: attestation.IdentifiersGitHub
			reflect.ValueOf(identifiers),
			// Third argument: *mysql.Cursor
			reflect.ValueOf(&mysql.Cursor{
				PerPage: 30,
			}),
		}

		// Start a timer to measure the query time
		start := time.Now()
		// Call the method with the provided arguments
		method.Call(args)
		elapsed := time.Since(start)
		fmt.Printf("Query time duration for %s: %s\n", methodName, elapsed)
		if i == 0 {
			// Skip the first run to avoid caching effects
			continue
		}
		totalElapsed += elapsed
		db.Close()
	}
	fmt.Printf("Average query time duration for %s: %s\n", methodName, totalElapsed/time.Duration(methodRunCount-1))
	return nil
}
