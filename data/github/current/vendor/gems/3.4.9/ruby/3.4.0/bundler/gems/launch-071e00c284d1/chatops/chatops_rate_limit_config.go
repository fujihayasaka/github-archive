package chatops

import (
	"context"
	"fmt"
	"strings"

	crpc "github.com/github/go-chatops/v2"
	"github.com/pkg/errors"
)

const (
	enable  = "enable"
	disable = "disable"
	get     = "get"
	clear   = "clear"
)

func (app *Application) rateLimitConfig(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	app.Logger.Log(ctx, "received chatop: rate_limit_config")

	switch cmd := r.Params["state"]; cmd {
	case get, enable, disable, clear:
		return app.rateLimitConfigCommand(ctx, r)
	default:
		return nil, errors.Errorf("%q is not a known sub-command for rate_limit_config", cmd)
	}
}

var (
	allowedRateLimiters = []string{
		"queue-build",
		"webhook",
	}

	errInvalidLimiter = fmt.Errorf("invalid command. rate limiter must be one of: %v", allowedRateLimiters)

	queueBuildKeys = map[string]string{
		"dark-mode": "launch:queue_rate_limits:use_dark_mode",
		"in-memory": "launch:queue_rate_limits:use_in_memory",
	}

	webhookKeys = map[string]string{
		"dark-mode": "launch:webhook_rate_limits:use_dark_mode",
		"in-memory": "launch:webhook_rate_limits:use_in_memory",
	}

	errInvalidSettingForLimiterFn = func(m map[string]string) error {
		keys := make([]string, 0)
		for k := range m {
			keys = append(keys, k)
		}
		return fmt.Errorf("invalid command. rate limiter must be one of: %v", keys)
	}
)

func (app *Application) rateLimitConfigCommand(ctx context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	setting := strings.TrimSpace(r.Params["setting"])
	if setting == "" {
		return nil, errors.New("Setting cannot be blank")
	}

	redisKey := ""
	switch r.Params["limiter"] {
	case "queue-build":
		key, ok := queueBuildKeys[setting]
		if !ok {
			return nil, errInvalidSettingForLimiterFn(queueBuildKeys)
		}
		redisKey = key
	case "webhook":
		key, ok := webhookKeys[setting]
		if !ok {
			return nil, errInvalidSettingForLimiterFn(queueBuildKeys)
		}
		redisKey = key
	default:
		return nil, errInvalidLimiter
	}

	switch cmd := r.Params["state"]; cmd {
	case get:
		current, err := app.ConfigSyncService.Get(ctx, redisKey)
		if err != nil {
			return &crpc.CommandResponse{Result: fmt.Sprintf("Error: %v", err)}, err
		}
		return &crpc.CommandResponse{Result: fmt.Sprintf("Success: %v is set to %v", redisKey, current)}, nil
	case enable, disable:
		wantToEnable := cmd == enable
		err := app.ConfigSyncService.Set(ctx, redisKey, wantToEnable)
		if err != nil {
			return &crpc.CommandResponse{Result: fmt.Sprintf("Error: %v", err)}, err
		}
		return &crpc.CommandResponse{Result: fmt.Sprintf("Success: %v is set to %v", redisKey, wantToEnable)}, nil
	case clear:
		err := app.ConfigSyncService.Clear(ctx, redisKey)
		if err != nil {
			return &crpc.CommandResponse{Result: fmt.Sprintf("Error: %v", err)}, err
		}
		return &crpc.CommandResponse{Result: fmt.Sprintf("Success: %v is cleared", redisKey)}, nil
	default:
		return nil, fmt.Errorf("%q is not a known command for rate_limit_config setings, expected one of: 'get', 'enable', 'disable', 'clear'", cmd)
	}
}
