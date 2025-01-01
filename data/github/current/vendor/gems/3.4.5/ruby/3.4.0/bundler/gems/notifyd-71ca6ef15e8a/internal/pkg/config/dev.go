// Package config implements a way to load configuration from the environment.
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/joho/godotenv"
)

const (
	// envFile holds the default file where we store development like configuration that is shared through
	// environment variables.
	envFile = ".env"
	// envLocalFile holds the file where developers can define overrides for configuration that are local
	// to their develoment environments.
	envLocalFile = ".env.local"
)

// LoadDotEnv takes care of loading the default setup for the development
// environment.
//
// One of the security requirements for new applications as of writing this
// (september 2021) is that environment secrets do not have defaults set up in
// the code and that the application fails when they are missing from the
// environment.
//
// Up until now we had been setting defaults for secrets as hardcoded values on
// the code, now we're leaving them blank. If they are missing loading the
// config will fail.
//
// In order to avoid developers from having to do any setup, we provide this so
// that notifyd's devenv works out of the box.
//
// Calls to LoadDotEnv on environments different than `test` or `development`
// are noop.
func LoadDotEnv() {
	env := os.Getenv("APP_ENV")

	if env != "test" && env != "development" {
		return
	}

	// in case it exists, give precedence to .env.local over .env
	files := []string{}
	if _, err := os.Stat(envPath(envLocalFile)); err == nil {
		files = append(files, envPath(envLocalFile))
	}
	files = append(files, envPath(envFile))

	err := godotenv.Load(files...)

	if err != nil {
		fmt.Printf("%s\n", err)
	}
}

// envPath returns the path of the `.env` file.
//
// godotenv uses the current working directory to load the `.env` file by
// default. The problem with that is when running tests the cwd isn't the
// project root so we need to help it a bit by doing this calculation.
func envPath(file string) string {
	_, current, _, _ := runtime.Caller(0)
	basepath := filepath.Dir(current)

	return filepath.Join(basepath, fmt.Sprintf("../../../%s", file))
}
