package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	transitionsapp "github.com/github/trust-metadata-api/internal/transitions/app"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const mySQLDBConnFormat = "%s:%s@tcp(%s:%s)/%s?parseTime=true"

var config transitionsapp.Config

// initConfig reads in config file and ENV variables
func initConfig(cmd *cobra.Command, _ []string) {
	viper.SetEnvPrefix("TMA")
	viper.AutomaticEnv()
	viper.SetEnvKeyReplacer(strings.NewReplacer("-", "_"))

	err := viper.BindPFlags(cmd.Flags())
	cobra.CheckErr(err)

	err = viper.Unmarshal(&config)
	cobra.CheckErr(err)

	config.MySQLDBConn = fmt.Sprintf(mySQLDBConnFormat,
		config.MySQLUser,
		config.MySQLPassword,
		config.MySQLHost,
		config.MySQLPort,
		config.MySQLDatabase)
}

func main() {
	rootCmd := &cobra.Command{Use: "transition"}
	rootCmd.CompletionOptions.DisableDefaultCmd = true
	rootCmd.AddCommand(initRunCommand(runCommand))

	if err := rootCmd.Execute(); err != nil {
		panic(err)
	}
}

// parse command line flags and environment variables
func initRunCommand(runFn func(*cobra.Command, []string) error) *cobra.Command {
	var cmdRun = &cobra.Command{
		Use:              "run",
		Short:            "Run the given database transition",
		PersistentPreRun: initConfig,
		RunE:             runFn,
	}

	// transition configuration
	cmdRun.Flags().Bool("dry-run", false, "whether to run the transition in dry run mode")
	cmdRun.Flags().Uint("id", 0, "the transition ID")
	cmdRun.Flags().Uint64("min-id", 0, "the minimum record ID")
	cmdRun.Flags().Uint64("max-id", 0, "the maximum record ID")
	cmdRun.Flags().Uint64("batch-size", 100, "the batch size for the transition: default 100")

	// database and env configuration
	cmdRun.Flags().StringP("app-env", "e", "staging", "environment")
	// primary DB configuration
	cmdRun.Flags().String("mysql-database", "", "MySQL database")
	cmdRun.Flags().String("mysql-host", "", "MySQL host address")
	cmdRun.Flags().String("mysql-port", "", "MySQL host port")
	cmdRun.Flags().String("mysql-user", "", "MySQL user")
	cmdRun.Flags().String("mysql-password", "", "MySQL password")
	// read-only replica DB configuration
	cmdRun.Flags().String("mysql-ro-database", "", "MySQL read only database")
	cmdRun.Flags().String("mysql-ro-host", "", "MySQL read only host address")
	cmdRun.Flags().String("mysql-ro-port", "", "MySQL read only host port")
	cmdRun.Flags().String("mysql-ro-user", "", "MySQL read only user")
	cmdRun.Flags().String("mysql-ro-password", "", "MySQL read only password")

	// Azure Blob Storage configuration
	cmdRun.Flags().String("azure-blob-account", "", "Azure Blob Storage account")
	cmdRun.Flags().String("azure-blob-container", "", "Azure Blob Storage container")

	return cmdRun
}

// run the command
func runCommand(_ *cobra.Command, _ []string) error {
	ctx := context.Background()

	// fail if required flags are not set
	if err := checkRequiredFlags(config); err != nil {
		return err
	}

	// https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/#test-runs
	if config.DryRun {
		fmt.Println("Running in dry-run mode")
		os.Exit(0)
	}

	// create a new transitions app and run it
	app, err := transitionsapp.New(config)
	if err != nil {
		log.Fatal(err)
	}

	return app.Run(ctx)
}

// checkRequiredFlags checks if the required flags are set
func checkRequiredFlags(c transitionsapp.Config) error {
	if c.BatchSize <= 0 {
		return fmt.Errorf("batch-size must be greater than 0")
	}
	return nil
}
