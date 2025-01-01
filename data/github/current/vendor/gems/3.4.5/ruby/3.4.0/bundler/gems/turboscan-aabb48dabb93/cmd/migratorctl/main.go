// Command migratorctl runs migrations (update the schema) and transitions (upgrade the data) against the Turboscan database.
package main

import (
	"fmt"
	"os"

	"github.com/github/turboscan/cmd/migratorctl/root"
	_ "github.com/go-sql-driver/mysql"
)

func main() {
	if err := root.MigratorCTLCmd.Execute(); err != nil {
		fmt.Printf("level=error message=%q\n", err)
		os.Exit(1)
	}
}
