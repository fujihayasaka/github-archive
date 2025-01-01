package useragent

import (
	"fmt"
)

const (
	app = "launch"
)

func GetUserAgent(env string) string {
	if env == "" {
		return app
	}
	return fmt.Sprintf("%s/%s", app, env)
}
