package chatops

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"strings"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/go-exceptions"

	"github.com/github/go-chatops/v2"
)

func defaultChatops(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) []chatops.Chatop {
	return []chatops.Chatop{
		hmacChatop(cfg),
		includedSnapshotsChatop(cfg, reporter, snapshotsSvc),
		excludeSnapshotChatop(cfg, reporter, snapshotsSvc),
		totalSnapshotsChatop(cfg, reporter, snapshotsSvc),
		uniqueRepositoriesChatop(cfg, reporter, snapshotsSvc),
	}
}

func NewChatopsHandler(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) (*chatops.Handler, error) {
	ns := chatops.NewNamespace("snap")
	ns.Help = "Chatops for Dependency Snapshots"

	for _, chatop := range defaultChatops(cfg, reporter, snapshotsSvc) {
		_, err := ns.Register(chatop)
		if err != nil {
			return nil, err
		}
	}

	handler, err := chatops.NewHandler(ns, cfg.ChatopsBaseURL)
	if err != nil {
		return nil, err
	}

	if cfg.ChatopsBotPublicKey != "" {
		block, _ := pem.Decode([]byte(cfg.ChatopsBotPublicKey))
		if block == nil {
			return nil, errors.New("pem decoding failed")
		}

		botKey, err := x509.ParsePKCS1PublicKey(block.Bytes)
		if err != nil {
			if strings.Contains(err.Error(), "(use ParsePKIXPublicKey instead for this key format)") {
				var potentialKey any
				potentialKey, err = x509.ParsePKIXPublicKey(block.Bytes)
				if err == nil {
					var ok bool
					botKey, ok = potentialKey.(*rsa.PublicKey)
					if !ok {
						return nil, errors.New("attempt to fallback to dev mode certificate failed, chatops cannot load")
					}
				}
			}

			if err != nil {
				return nil, err
			}
		}
		handler.AddBot(botKey)
	}

	return handler, nil
}

func hmacChatop(cfg *config.Config) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"hmac",
		"hmac - Disabled. Please use `.dg hmac` instead.",
		"hmac",
		coalesceCommand(func(_ context.Context, _ *chatops.CommandRequest) (string, error) {
			return "This chatop is disabled. Please use `.dg hmac` instead.", nil
		}),
	)
}

func includedSnapshotsChatop(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"get-included-snapshots",
		"get-included-snapshots <repositoryID> - Disabled. Please use stafftools to get a list of included snapshots for a repository.",
		`get-included-snapshots\s+(?<repositoryID>[^\s/]+)`,
		coalesceCommand(func(_ context.Context, _ *chatops.CommandRequest) (string, error) {
			return "This chatop is disabled. Please use stafftools to get a list of included snapshots for a repository.", nil
		},
		))
}

func excludeSnapshotChatop(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"exclude-snapshot",
		"exclude-snapshot <repositoryID> <snapshotID> - Disabled. Please use stafftools to exclude snapshots for a repository.",
		`exclude-snapshot\s+(?<repositoryID>[^\s]+)\s+(?<snapshotID>[^\s]+)\s*`,
		coalesceCommand(func(ctx context.Context, req *chatops.CommandRequest) (string, error) {
			return "This chatop is disabled. Please use stafftools to exclude snapshots for a repository.", nil
		},
		))
}

func uniqueRepositoriesChatop(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"unique-repositories",
		"unique-repositories - Gets basic information about what unique repositories have snapshot data stored. Excludes internal snapshots.",
		`unique-repositories\s*`,
		coalesceCommand(func(ctx context.Context, req *chatops.CommandRequest) (string, error) {
			counts, err := snapshotsSvc.UniqueRepositoryCounts(ctx)
			if err != nil {
				return "", err
			}

			return fmt.Sprintf("Counted %v unique repositories total, %v in the last day and %v in the last week", counts.Total, counts.InLastDay, counts.InLastWeek), nil
		},
		))
}

func totalSnapshotsChatop(cfg *config.Config, reporter *exceptions.Reporter, snapshotsSvc interfaces.SnapshotsService) *chatops.GenericChatop {
	return chatops.NewGenericChatop(
		"total-snapshots",
		"total-snapshots - Gets basic information about how many snapshots have been created",
		`total-snapshots\s*`,
		coalesceCommand(func(ctx context.Context, req *chatops.CommandRequest) (string, error) {
			counts, err := snapshotsSvc.TotalSnapshotCounts(ctx)
			if err != nil {
				return "", err
			}

			return fmt.Sprintf("Counted %v snapshots total, %v in the last day and %v in the last week", counts.Total, counts.InLastDay, counts.InLastWeek), nil
		},
		))
}

// coalesceCommand is a gnarly little function that is enabling us to return string for our command functions instead of inlining the creation of responses everywhere.
func coalesceCommand(wrapped func(ctx context.Context, req *chatops.CommandRequest) (string, error)) func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
	return func(ctx context.Context, req *chatops.CommandRequest) (*chatops.CommandResponse, error) {
		message, err := wrapped(ctx, req)
		if err != nil {
			return nil, err
		}

		return &chatops.CommandResponse{
			Result: message,
		}, nil
	}
}
