// Package dag contains the implementation to simply traverse a DAG in a distributed way using
// Redis as the storage backend.
package dag

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/go-redis/redis/v8"
)

type (
	// RedisDAG is a simple Redis-backed implementation to traverse a DAG
	RedisDAG struct {
		client                *redis.Client
		addNodeScript         string
		markAsProcessedScript string
		logger                log.Logger
	}

	// ID is the type for the node ID
	ID string
)

var (
	// Catch for interface implementation
	_ DAG = &RedisDAG{}

	//go:embed script/*.lua
	luaScripts embed.FS
)

const (
	addNodePath         = "script/add_node.lua"
	markAsProcessedPath = "script/mark_as_processed.lua"
)

// NewRedisDAG creates a new RedisDAG
func NewRedisDAG(client *redis.Client, logger log.Logger) (*RedisDAG, error) {
	// Read Lua scripts
	addNode, err := luaScripts.ReadFile(addNodePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read add node lua script: %w", err)
	}
	mark, err := luaScripts.ReadFile(markAsProcessedPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read mark as processed lua script: %w", err)
	}
	logger = logger.WithFields(kvp.String("component", "redis-dag"))
	return &RedisDAG{
		client:                client,
		addNodeScript:         string(addNode),
		markAsProcessedScript: string(mark),
		logger:                logger,
	}, nil
}

// AddNode adds a node with the given ID and its dependencies.
func (r *RedisDAG) AddNode(ctx context.Context, namespace string, kind NodeKind, id ID, dependencies ...Node) error {
	if namespace == "" {
		return errors.New("namespace must not be empty")
	}

	depIDs := make([]string, 0, len(dependencies))
	for i := range dependencies {
		depIDs = append(depIDs, fmt.Sprintf("%s:%s", dependencies[i].Kind.String(), dependencies[i].ID))
	}

	r.logger.Info("redis adding node", kvp.String("id", string(id)), kvp.String("kind", kind.String()), kvp.Any("dependencies", depIDs))

	argKeys := []string{namespace, kind.String(), string(id)}
	if _, err := r.client.Eval(ctx, r.addNodeScript, argKeys, depIDs).Result(); err != nil {
		return fmt.Errorf("failed to add node: %w", err)
	}
	return nil
}

// MarkAsProcessed marks the given nodes as processed. This triggers the eligibility of the
// dependent nodes if this was the last dependency.
func (r *RedisDAG) MarkAsProcessed(ctx context.Context, namespace string, nodes []Node) error {
	if namespace == "" {
		return errors.New("namespace must not be empty")
	}

	ids := make([]string, 0, len(nodes))
	for i := range nodes {
		ids = append(ids, fmt.Sprintf("%s:%s", nodes[i].Kind.String(), nodes[i].ID))
	}
	r.logger.Info("redis marking as processed", kvp.Any("ids", ids))

	if _, err := r.client.Eval(ctx, r.markAsProcessedScript, []string{namespace}, ids).Result(); err != nil {
		return fmt.Errorf("failed to mark as processed: %w", err)
	}
	return nil
}

// EligibleNodes returns the list of nodes that are eligible to be processed because their
// dependencies have been fulfilled. This function assumes that the values stored in the
// "eligible_nodes" set are "kind:id" strings.
func (r *RedisDAG) EligibleNodes(ctx context.Context, namespace string) ([]Node, error) {
	if namespace == "" {
		return nil, errors.New("namespace must not be empty")
	}

	ids, err := r.client.SMembers(ctx, namespace+":eligible_nodes").Result()
	if err != nil {
		return nil, fmt.Errorf("failed to get eligible nodes: %w", err)
	}

	var nodes []Node
	for _, id := range ids {
		split := strings.SplitN(id, ":", 2)
		node := Node{
			ID:   ID(split[1]),
			Kind: NodeKindFromString(split[0]),
		}
		if node.Kind == UnknownNode {
			r.logger.Warn("unknown node kind, skipping node", kvp.String("id", string(node.ID)))
			continue
		}
		nodes = append(nodes, node)
	}

	return nodes, nil
}
