package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/console"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/rest"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/telemetry"
	"go.opentelemetry.io/otel/trace"

	stats "github.com/github/go-stats"
)

// todo: more https://www.digitalocean.com/community/tutorials/how-to-use-the-flag-package-in-go
func main() {

	deleteDocuments := flag.Bool("delete-documents", false, "Delete all the items in current collection")
	deleteCollections := flag.Bool("delete-collections", false, "Delete all the collections in current database")
	deleteDatabases := flag.Bool("delete-databases", false, "Delete all in current database")
	withUuidOnly := flag.Bool("with-uuid-only", false, "Limits database deletes to only those with a UUID in the name (i.e. the ones created by integration tests)")
	deleteDatabasesWithPrefix := flag.String("delete-database-with-prefix-only", "", "Limits database deletes to only those with a prefix in the name")
	forceAll := flag.Bool("force-all", false, "By default deletes will only run in context of a user. Force will delete everyone else's too)")
	targetAccount := flag.String("target-account", "", "Specify which cosmos db account to target (e.g. billing-platform-ci)")
	doDBConsole := flag.Bool("query", false, "Launch DB Console for currently set remote")
	cfg, err := config.Load()
	if err != nil {
		log.WithError(err).Fatal("failed to load config")
	}

	telem, err := telemetry.NewFromEnv()
	if err != nil {
		log.WithError(err).Fatal("Failed to initialize telemetry")
	}

	logger := cfg.ConfigureLogger(telem.Logger, "BillingPlatformCLI")
	statter := cfg.StatsClient()
	statter = statter.WithTags(stats.Tags{"env": cfg.Environment, "service": "cli"})
	statter.Run()
	defer statter.Stop()
	logger.Info("Starting CLI")
	tracer := telem.Tracer.Tracer

	if cfg.IsProduction() {
		logger.Fatal("This is a production environment, cli is not allowed to run here")
	}

	if *targetAccount != "" {
		fmt.Println("Fetching connection strings for", *targetAccount)

		pwd, err := exec.Command("pwd").Output()
		if err != nil {
			logger.WithError(err).Fatal("failed to execute pwd command")
		}

		// get-az-account-endpoints is a script that echos the connection strings from az-resource-helpers
		path := fmt.Sprintf("%s/script/helpers/get-az-account-endpoints", strings.TrimSpace(string(pwd)))
		cmd := exec.Command(path)

		// We have to set SQL_ACCOUNT_NAME=*targetAccount and DEV_COSMOS_KEY= to get the connection strings for targetting account
		// from az-resource-helpers
		sqlAccountName := fmt.Sprintf("SQL_ACCOUNT_NAME=%s", *targetAccount)
		devCosmosKey := "DEV_COSMOS_KEY="

		cmd.Env = append(os.Environ(), sqlAccountName, devCosmosKey)
		out, err := cmd.Output()
		if err != nil {
			logger.WithError(err).Fatal("Failed to execute get-az-account-endpoints")
		}

		variables := strings.Fields(string(out))
		if len(variables) == 1 {
			fmt.Println("Setting gateway endpoint to account endpoint")
			variables = append(variables, variables[0])
		}

		if len(variables) != 2 {
			logger.Fatal("expected 2 variables from get-az-account-endpoints")
		}

		accountEndPoint, accountGatewayEndPoint := variables[0], variables[1]
		cfg.DBConnectionString = accountEndPoint
		cfg.DBGatewayConnectionString = accountGatewayEndPoint

		err = cfg.LoadDB()
		if err != nil {
			logger.WithError(err).Fatal("failed to reload db config")
		}
	}

	connection, _, err := db.NewDBConnections(cfg)
	if err != nil {
		logger.WithError(err).Fatal("failed to create db connection")
	}

	switch {
	case *deleteDocuments:
		executeDeleteAllDocuments(cfg, logger, statter, tracer)
	case *deleteCollections:
		executeDeleteAllCollections(cfg, logger, connection)
	case *deleteDatabases:
		console.ExecuteDeleteAllDatabases(cfg, logger, connection, *withUuidOnly, *forceAll)
	case *deleteDatabasesWithPrefix != "":
		console.ExecuteDeleteDatabasesWithPrefix(cfg, logger, connection, *deleteDatabasesWithPrefix)
	case *doDBConsole:
		console.ExecuteDBConsole(cfg, logger, connection)
	default:
		fmt.Println("No action specified! Exiting...")
		fmt.Println("Use -h for help")
	}
}

func executeDeleteAllCollections(cfg *config.Config, logger log.Logger, connection *db.Connection) {
	fmt.Println("Deleting all the collections in current database", cfg.DatabaseEndPoint, cfg.DatabaseName)
	sm := db.NewSchemaManagement(cfg, connection)

	items, err := rest.GetAllContainersForDatabase(cfg, cfg.DatabaseName)

	if err != nil {
		logger.WithError(err).Fatal("failed to get all containers for a database")
	}

	context := context.Background()
	for _, item := range items {
		err := sm.RemoveCollection(context, item)
		if err != nil {
			logger.WithError(err).Fatal("failed to remove collection")
		}
	}

	fmt.Println("Done", len(items), "items deleted")
}

func executeDeleteAllDocuments(cfg *config.Config, logger log.Logger, statter stats.Client, tracer trace.Tracer) {
	fmt.Println("Deleting all the items in current collection", cfg.DatabaseEndPoint, cfg.DatabaseName, cfg.ContainerName)

	readWriteDB := db.NewDatabase(cfg, logger, statter, tracer)

	items, err := rest.GetAllDocumentKeys(cfg)
	if err != nil {
		logger.WithError(err).Fatal("failed to get all document keys")
	}
	context := context.Background()
	for _, item := range items {
		err := readWriteDB.DeleteWithOptions(context, logger, item, nil)
		if err != nil {
			logger.WithError(err).Fatal("failed to delete item")
		}
	}

	fmt.Println("Done", len(items), "items deleted")
}
