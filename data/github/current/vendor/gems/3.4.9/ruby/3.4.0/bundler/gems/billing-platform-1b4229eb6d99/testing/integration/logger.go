package integration

import (
	"fmt"
	"os"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type IntegrationLogger struct {
	log.Logger

	verbose              bool
	testFile             *os.File
	t                    *testing.T
	uniqueCollectionName string
	uniqueDatabaseName   string
}

func (i *IntegrationLogger) ForceInfo(msg string, fields ...kvp.Field) {
	i.Info(msg, fields...)
	_, err := i.testFile.WriteString(fmt.Sprintf("%s:%s => %s%v\n", i.uniqueDatabaseName, i.uniqueCollectionName, msg, fields))
	if err != nil {
		i.t.Fatalf("Failed to write to test file: %v", err)
	}
}

func (i *IntegrationLogger) Info(msg string, fields ...kvp.Field) {
	if i.verbose {
		i.Logger.Info(msg, fields...)
	}
	_, err := i.testFile.WriteString(fmt.Sprintf("%s:%s => %s%v\n", i.uniqueDatabaseName, i.uniqueCollectionName, msg, fields))
	if err != nil {
		i.t.Fatalf("Failed to write to test file: %v", err)
	}
}

func (i *IntegrationLogger) Error(msg string, fields ...kvp.Field) {
	if i.verbose {
		i.Logger.Error(msg, fields...)
	}
	_, err := i.testFile.WriteString(fmt.Sprintf("%s => ERROR: %s%v\n", i.uniqueCollectionName, msg, fields))
	if err != nil {
		i.t.Fatalf("Failed to write to test file: %v", err)
	}
}

func (i *IntegrationLogger) WithError(err error) log.Logger {
	return &IntegrationLogger{
		Logger:               i.Logger.WithError(err),
		verbose:              i.verbose,
		testFile:             i.testFile,
		t:                    i.t,
		uniqueCollectionName: i.uniqueCollectionName,
		uniqueDatabaseName:   i.uniqueDatabaseName,
	}
}
