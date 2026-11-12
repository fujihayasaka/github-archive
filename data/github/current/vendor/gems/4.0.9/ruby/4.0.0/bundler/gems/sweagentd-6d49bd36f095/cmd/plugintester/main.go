// Command plugintester is a small utility for testing plugin service operations
// against real infrastructure. Configuration is loaded from the environment
// (same .env files and env vars used by the main service).
//
// Usage:
//
// plugintester info  -spec owner/repo
// plugintester agent -spec sentry@copilot-plugins -agent reviewer
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/github/sweagentd/internal/cache"
	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/plugins"
	"github.com/github/sweagentd/internal/spokes"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	mode := os.Args[1]
	fs := flag.NewFlagSet(mode, flag.ExitOnError)
	pluginSpec := fs.String("spec", "", "plugin spec (e.g. owner/repo, name@marketplace, or full URL)")
	agentName := fs.String("agent", "", "agent name to fetch (required for 'agent' mode)")
	err := fs.Parse(os.Args[2:])
	if err != nil {
		os.Exit(1)
	}

	if *pluginSpec == "" {
		_, _ = fmt.Fprintln(os.Stderr, "error: -spec is required")
		fs.Usage()
		os.Exit(1)
	}

	var runErr error
	switch mode {
	case "info":
		runErr = runInfo(*pluginSpec)
	case "agent":
		if *agentName == "" {
			_, _ = fmt.Fprintln(os.Stderr, "error: -agent is required for 'agent' mode")
			fs.Usage()
			os.Exit(1)
		}
		runErr = runAgent(*pluginSpec, *agentName)
	default:
		_, _ = fmt.Fprintf(os.Stderr, "unknown mode %q\n", mode)
		printUsage()
		os.Exit(1)
	}
	if runErr != nil {
		_, _ = fmt.Fprintf(os.Stderr, "error: %v\n", runErr)
		os.Exit(1)
	}
}

func printUsage() {
	_, _ = fmt.Fprintln(os.Stderr, "usage: plugintester <mode> [flags]")
	_, _ = fmt.Fprintln(os.Stderr, "modes: info, agent")
	_, _ = fmt.Fprintln(os.Stderr, "run 'plugintester <mode> -help' for mode-specific flags")
}

// buildService creates a plugins.Service wired to real infrastructure using
// the standard config.Load() path, mirroring how cmd/http initializes its
// dependencies.
func buildService() (*plugins.Service, error) {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		return nil, goerrors.Errorf("loading config: %w", err)
	}

	obsv := observability.NewNoopExporters()

	ffClient := featureflags.NewNoopClient(nil)

	cacheStore, err := cache.NewCacheStore(ctx, cfg, obsv)
	if err != nil {
		return nil, goerrors.Errorf("creating cache store: %w", err)
	}

	ghTwirp, err := githubtwirp.NewClientFromConfig(obsv, ffClient, cacheStore, cfg)
	if err != nil {
		return nil, goerrors.Errorf("creating github twirp client: %w", err)
	}

	spokesClient, err := spokes.NewClientFromConfig(obsv, cfg)
	if err != nil {
		return nil, goerrors.Errorf("creating spokes client: %w", err)
	}

	svc := plugins.NewService(obsv, spokesClient, ghTwirp, cfg.GitHubServerURL)

	return svc, nil
}

func runInfo(pluginSpec string) error {
	svc, err := buildService()
	if err != nil {
		return err
	}

	meta, err := resolvePlugin(svc, pluginSpec)
	if err != nil {
		return err
	}

	plugin, err := svc.GetPlugin(context.Background(), meta)
	if err != nil {
		return goerrors.Errorf("GetPlugin: %w", err)
	}

	fmt.Println("=== Plugin Info ===")
	return printJSON(plugin)
}

func runAgent(pluginSpec, agentName string) error {
	svc, err := buildService()
	if err != nil {
		return err
	}

	meta, err := resolvePlugin(svc, pluginSpec)
	if err != nil {
		return err
	}

	plugin, err := svc.GetPlugin(context.Background(), meta)
	if err != nil {
		return goerrors.Errorf("GetPlugin: %w", err)
	}

	agent, err := svc.GetPluginAgent(context.Background(), plugin, agentName)
	if err != nil {
		return goerrors.Errorf("GetPluginAgent(%s): %w", agentName, err)
	}

	fmt.Printf("=== Agent: %s ===\n", agentName)
	fmt.Printf("Name:         %s\n", agent.Name())
	fmt.Printf("DisplayName:  %s\n", agent.DisplayName())
	fmt.Printf("Description:  %s\n", agent.Description())
	fmt.Printf("Model:        %s\n", agent.Model())
	fmt.Printf("Tools:        %v\n", agent.Tools())
	fmt.Printf("Prompt:       %s\n", truncate(agent.Prompt(), 200))
	return nil
}

// resolvePlugin resolves a plugin spec string into PluginMetadata using ResolvePluginRepos.
func resolvePlugin(svc *plugins.Service, pluginSpec string) (plugins.PluginMetadata, error) {
	resolved, err := svc.ResolvePluginRepos(context.Background(), &plugins.SettingsJSON{
		EnabledPlugins: map[string]bool{pluginSpec: true},
	})
	if err != nil {
		return plugins.PluginMetadata{}, goerrors.Errorf("ResolvePluginRepos: %w", err)
	}
	if len(resolved) == 0 {
		return plugins.PluginMetadata{}, goerrors.Errorf("plugin %q not found", pluginSpec)
	}
	return resolved[0], nil
}

func printJSON(v *plugins.Plugin) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}
