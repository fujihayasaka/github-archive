package utils

import (
	"path"
	"runtime"

	"github.com/github/actions-usage-metrics/internal/config"
)

func GetDevConfig[T any]() T {
	cfg, err := config.LoadFromFile[T](getDevConfigFile())
	if err != nil {
		panic(err)
	}

	return *cfg
}

func getDevConfigFile() string {
	_, filename, _, _ := runtime.Caller(0)
	return path.Join(path.Dir(filename), "../../config/kustomize/devoverlays/dev/config.env")
}
