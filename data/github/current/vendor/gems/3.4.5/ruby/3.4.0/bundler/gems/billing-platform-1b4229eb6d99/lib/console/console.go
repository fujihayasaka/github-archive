package console

import (
	"context"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/carmark/pseudo-terminal-go/terminal"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/rest"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"

	"github.com/mattn/go-colorable"
	json "github.com/neilotoole/jsoncolor"
)

func OutputJSON(data []map[string]interface{}) {
	var enc *json.Encoder

	// Note: this check will fail if running inside Goland (and
	// other IDEs?) as IsColorTerminal will return false.
	if json.IsColorTerminal(os.Stdout) {
		// Safe to use color
		out := colorable.NewColorable(os.Stdout) // needed for Windows
		enc = json.NewEncoder(out)
		// enc.SetIndent("", "  ")
		// DefaultColors are similar to jq
		clrs := json.DefaultColors()

		// Change some values, just for fun
		clrs.Bool = json.Color("\x1b[36m") // Change the bool color
		clrs.String = json.Color{}         // Disable the string color

		enc.SetColors(clrs)
	} else {
		// Can't use color; but the encoder will still work
		enc = json.NewEncoder(os.Stdout)
	}

	for _, item := range data {
		if err := enc.Encode(item); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
}

func ExecuteDBConsole(cfg *config.Config, logger log.Logger, connection *db.Connection) {
	term, err := terminal.NewWithStdInOut()
	if err != nil {
		panic(err)
	}
	defer term.ReleaseFromStdInOut() // defer this
	fmt.Println("Ctrl-D to break")
	fmt.Println("Terminal prompt is <database>@<container>> where <database> is the current database and <container> is the current container")
	fmt.Println("Command history 'arrow up' is supported but not yet aross sessions")
	fmt.Println("USAGE:")
	fmt.Println("\tshow databases: list all current dbs/containres")
	fmt.Println("\tuse database <database>: use (and create idempotently) a database. 'GITHUB_USERNAME' env variable will be appended to the database name")
	fmt.Println("\tdelete databases: delete all databases in current server for currnet user")
	fmt.Println("\tinsert <json>: insert a json item into the current database. cosmos requires 'id' and (case sensitive) 'partitionKey' fields")
	fmt.Println("\t<query>: execute a query against the current database. cosmos requires 'SELECT * FROM c' to query all items in the current database.\n\t\tSome feautres won't work as cross parition queries...\r\n\t\tSpecifically I know of `OFFSET x LIMIT x` and `COUNT(1)` as not working today")
	term.SetPrompt(fmt.Sprintf("%s@%s> ", cfg.DatabaseName, cfg.ContainerName))

	sm := db.NewSchemaManagement(cfg, connection)
	err = sm.EnsureCollectionAndDatabaseExists(context.Background(), cfg.ContainerName, cfg.DatabaseName)
	if err != nil {
		panic(err)
	}

	line, err := term.ReadLine()
	for {
		if err == io.EOF {
			_, err := term.Write([]byte(line))
			if err != nil {
				panic(err)
			}
			fmt.Println()
			return
		}
		if err == nil {
			switch {
			case line == strings.ToLower("show databases"):
				showDataBases(cfg)
			case strings.Contains(strings.ToLower(line), "use database"):
				useDB(cfg, line, sm, term)
			case strings.Contains(strings.ToLower(line), "delete databases"):
				ExecuteDeleteAllDatabases(cfg, logger, connection, false, false)
				cfg.DatabaseName = ""
				cfg.ContainerName = ""
				term.SetPrompt(fmt.Sprintf("%s@%s> ", cfg.DatabaseName, cfg.ContainerName))
			case strings.Contains(strings.ToLower(line), "insert "):
				insertItem(cfg, line, logger)
			default:
				query(cfg, line, term)
			}
		}
		line, err = term.ReadLine()
	}
}

func insertItem(cfg *config.Config, line string, logger log.Logger) {
	jsonItem := strings.TrimSpace(line[strings.Index(strings.ToLower(line), "insert")+len("insert"):])

	var item interface{}
	err := json.Unmarshal([]byte(jsonItem), &item)
	if err != nil {
		fmt.Println("Unale to parse item to insert", err, item)
		return
	}
	if item == nil {
		fmt.Println("Item to insert is nil")
		return
	}
	if item.(map[string]interface{})["id"] == nil {
		fmt.Println("Item to insert does not have an id")
		return
	}

	pk := item.(map[string]interface{})["partitionKey"]
	if pk == nil {
		fmt.Println("Item to insert does not have a partitionKeby")
		return
	}

	createdItem, err := rest.CreateDocument(cfg, jsonItem, pk.(string))
	if err != nil {
		fmt.Println("Unable to insert item", err)
		return
	}
	OutputJSON([]map[string]interface{}{createdItem})
}

func useDB(cfg *config.Config, line string, sm *db.SchemaManagement, term *terminal.Terminal) {
	database := strings.TrimSpace(strings.Replace(strings.ToLower(line), "use database", "", 1))
	if database == "" {
		fmt.Println("Please specify a database")
		return
	}
	userName := os.Getenv("GITHUB_USER")
	if userName == "" {
		fmt.Println("Please set GITHUB_USER environment variable")
		return
	}
	database = userName + "-" + database
	fmt.Println("Using database", database)
	err := sm.EnsureCollectionAndDatabaseExists(context.Background(), database, database)
	if err != nil {
		fmt.Println(err)
		return
	}
	cfg.DatabaseName = database
	cfg.ContainerName = database
	term.SetPrompt(fmt.Sprintf("%s@%s> ", cfg.DatabaseName, cfg.ContainerName))
}

func showDataBases(cfg *config.Config) {
	databases, err := rest.GetAllDatabasesForServer(cfg)
	if err != nil {
		fmt.Println(err)
		return
	}
	userName := os.Getenv("GITHUB_USER")
	fmt.Println("Databases : Containers for", userName)
	for _, database := range databases {
		if strings.HasPrefix(database, userName) {
			containers, err := rest.GetAllContainersForDatabase(cfg, database)
			if err != nil {
				fmt.Println(err)
				return
			}
			for _, container := range containers {
				fmt.Println("\t", database, ":", container)
			}
		}
	}
}

// handleCmd parses the given commands
func query(cfg *config.Config, query string, term *terminal.Terminal) {
	items, err := rest.Query(cfg, query)
	if err != nil {
		fmt.Println(err)
	}

	OutputJSON(items)
}

func ExecuteDeleteAllDatabases(cfg *config.Config, logger log.Logger, connection *db.Connection, withUUIDOnly bool, forceAll bool) {
	fmt.Println("Deleting all the databases in current server", cfg.DatabaseEndPoint, "withUuidOnly", withUUIDOnly, "forceAll", forceAll)
	sm := db.NewSchemaManagement(cfg, connection)

	items, err := rest.GetAllDatabasesForServer(cfg)
	if err != nil {
		logger.Fatal("Failed to get databases", kvp.String("error", err.Error()))
	}

	userName := os.Getenv("GITHUB_USER")
	if userName == "" && !forceAll {
		logger.Fatal("GITHUB_USER environment variable must be set to a non-empty value")
	}

	r := regexp.MustCompile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
	deletedCount := 0
	context := context.Background()
	g, ctx := errgroup.WithContext(context)
	g.SetLimit(4)
	for _, item := range items {
		itemKey := item
		if forceAll || strings.HasPrefix(itemKey, userName) && !(withUUIDOnly && !r.MatchString(itemKey)) {
			g.Go(func() error {
				err := sm.RemoveDatabase(ctx, itemKey)
				if err != nil && !forceAll {
					return errors.Wrap(err, fmt.Sprintf("failed to delete database %s", itemKey))
				}

				return nil
			})

			fmt.Printf("Scheduled for deletion %s\n", itemKey)
			deletedCount++
		}
	}

	if err := g.Wait(); err != nil {
		logger.Fatal("Failed to delete databases", kvp.String("error", err.Error()))
	}

	fmt.Printf("Done %d items deleted\n", deletedCount)
}

// ExecuteDeleteAllDatabases deletes all CI databases in the current server
// CI databases will have the prefix "billing-platform-ci-*"
func ExecuteDeleteDatabasesWithPrefix(cfg *config.Config, logger log.Logger, connection *db.Connection, prefix string) {
	if prefix == "" {
		logger.Fatal("prefix must be provided")
	}

	logger.Info("Deleting all the databases in current server", kvp.String("prefix", prefix), kvp.String("endpoint", cfg.DatabaseEndPoint))
	sm := db.NewSchemaManagement(cfg, connection)

	items, err := rest.GetAllDatabasesForServer(cfg)
	if err != nil {
		logger.Fatal("Failed to get databases", kvp.String("error", err.Error()))
	}
	logger.Info("Got total databases", kvp.Int("count", len(items)))

	deletedCount := 0
	ctx := context.Background()
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(4)
	for _, item := range items {
		itemKey := item
		if strings.HasPrefix(itemKey, prefix) {
			g.Go(func() error {
				logger.Info("Deleting CI database", kvp.String("database", itemKey))
				err := sm.RemoveDatabase(ctx, itemKey)
				time.Sleep(1 * time.Second)
				if err != nil {
					return errors.Wrap(err, fmt.Sprintf("failed to delete database %s", itemKey))
				}

				return nil
			})

			logger.Info("Scheduled for deletion", kvp.String("database", itemKey))
			deletedCount++
		}
	}

	if err := g.Wait(); err != nil {
		logger.Fatal("Failed to delete databases", kvp.String("error", err.Error()))
	}

	logger.Info("Deletion done.", kvp.Int("count", deletedCount))
}
