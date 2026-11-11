//go:build integration

package test

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/dependency-snapshots-api/internal/dependabot"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/storage"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/dependency-snapshots-api/pkg/proto/entities"

	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/references"
	"github.com/github/spokes-proto/gen/go/v1/types"

	stats "github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

var (
	serviceAddr        = "http://localhost:9597"
	snapshotDeprecated = `{
  "version": 10,
  "sha": "d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
  "ref": "refs/heads/main",
  "job": {
    "name": "build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (json)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:25:00Z",
  "manifests": {
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "@actions/core": {
          "purl": "pkg:npm/%40actions/core@1.1.9",
          "dependencies": [
            "@actions/http-client"
          ]
        },
        "@actions/http-client": {
          "purl": "pkg:npm/%40actions/http-client@1.0.7",
          "dependencies": [
            "tunnel"
          ]
        },
        "tunnel": {
          "purl": "pkg:npm/tunnel@0.0.6"
        }
      }
    }
  }
}`

	snapshot = `{
  "version": 10,
  "sha": "d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
  "ref": "refs/heads/main",
  "job": {
    "correlator": "build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (json)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:25:00Z",
  "manifests": {
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "@actions/core": {
          "package_url": "pkg:npm/%40actions/core@1.1.9",
          "dependencies": [
            "@actions/http-client"
          ]
        },
        "@actions/http-client": {
          "package_url": "pkg:npm/%40actions/http-client@1.0.7",
          "dependencies": [
            "tunnel"
          ]
        },
        "tunnel": {
          "package_url": "pkg:npm/tunnel@0.0.6"
        }
      }
    }
  }
}`

	internalSnapshot = `{
  "version": 0,
  "sha": "aaaaaaaaaaaaaaaaaaaaab9b90268bd7dedf4678",
  "internal": true,
  "ref": "refs/heads/main",
  "job": {
    "correlator": "build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (json)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:25:00Z",
  "manifests": {
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "@actions/core": {
          "package_url": "pkg:npm/%40actions/core@1.1.9",
          "dependencies": [
            "@actions/http-client"
          ]
        },
        "@actions/http-client": {
          "package_url": "pkg:npm/%40actions/http-client@1.0.7",
          "dependencies": [
            "tunnel"
          ]
        },
        "tunnel": {
          "package_url": "pkg:npm/tunnel@0.0.6"
        }
      }
    }
  }
}`

	snapshotWithBadPurl = `{
  "version": 0,
  "sha": "d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
  "ref": "refs/heads/main",
  "job": {
    "correlator": "build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (json)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:25:00Z",
  "manifests": {
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "@actions/core": {
          "package_url": "/npm/%40actions/core@1.1.9",
          "dependencies": [
            "@actions/http-client"
          ]
        }
      }
    }
  }
}`

	snapshotWithBadPurlType = `{
  "version": 0,
  "sha": "d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
  "ref": "refs/heads/main",
  "job": {
    "correlator": "build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (json)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:25:00Z",
  "manifests": {
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "@actions/core": {
          "package_url": "pkg:blorgle/%40actions/core@1.1.9",
          "dependencies": [
            "@actions/http-client"
          ]
        }
      }
    }
  }
}`

	dependabotSnapshot = &proto.CreateDependabotSnapshotRequest{
		Payload: &entities.Snapshot{
			Version: 10,
			Job: &entities.Snapshot_Job{
				Id:         "0",
				Correlator: "build",
			},
			Sha: "d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
			Ref: "refs/heads/main",
			Detector: &entities.Snapshot_Detector{
				Name:    "integration tests (json)",
				Url:     "github/com/github/dependency-snapshots-api/detector",
				Version: "0.0.1",
			},
			Scanned: timestamppb.New(time.Date(2021, 12, 13, 20, 25, 0, 0, time.UTC)),
			Manifests: map[string]*entities.Manifest{
				"package-lock.json": {
					Name: "package-lock.json",
					File: &entities.Manifest_File{
						SourceLocation: "package-lock.json",
					},
					Resolved: map[string]*entities.Dependency{
						"@actions/core": {
							PackageUrl: "pkg:npm/%40actions/core@1.1.9",
							Dependencies: []string{
								"@actions/http-client",
							},
						},
						"@actions/http-client": {
							PackageUrl: "pkg:npm/%40actions/http-client@1.0.7",
							Dependencies: []string{
								"tunnel",
							},
						},
						"tunnel": {
							PackageUrl: "pkg:npm/tunnel@0.0.6",
						},
					},
				},
			},
		},
	}

	snapshotsClient    = proto.NewSnapshotsServiceProtobufClient(serviceAddr, http.DefaultClient)
	dependabotClient   = proto.NewDependabotServiceProtobufClient(serviceAddr, http.DefaultClient)
	dependenciesClient = proto.NewDependenciesServiceProtobufClient(serviceAddr, http.DefaultClient)
)

func TestMain(m *testing.M) {
	if overrideAddr := os.Getenv("SERVICE_ADDRESS"); len(overrideAddr) > 0 {
		serviceAddr = overrideAddr
		snapshotsClient = proto.NewSnapshotsServiceProtobufClient(serviceAddr, http.DefaultClient)
		dependenciesClient = proto.NewDependenciesServiceProtobufClient(serviceAddr, http.DefaultClient)
	}

	serveSpokes()

	os.Exit(m.Run())
}

func TestCreateAndGetDependencySnapshot(t *testing.T) {
	repositoryID := makeRepositoryID()

	snapshotID := createSnapshot(t, repositoryID, snapshot)
	resp := getSnapshot(t, repositoryID, snapshotID)

	assert.JSONEq(t, snapshot, string(resp.Payload), "The submitted snapshot didn't match the response from GetSnapshot")
	assert.Equal(t, repositoryID, resp.RepositoryId, "Requested repo id %d didn't match repo id %d in response", repositoryID, resp.RepositoryId)
	assert.Equal(t, snapshotID, resp.SnapshotId, "Snapshot id didn't match")
}

func TestCreateAndGetDependabotSnapshot(t *testing.T) {
	repositoryID := makeRepositoryID()

	snapshotID := createDependabotSnapshot(t, repositoryID, dependabotSnapshot)
	resp := getSnapshot(t, repositoryID, snapshotID)

	assert.JSONEq(t, snapshot, string(resp.Payload), "The submitted snapshot didn't match the response from GetSnapshot")
	assert.Equal(t, repositoryID, resp.RepositoryId, "Requested repo id %d didn't match repo id %d in response", repositoryID, resp.RepositoryId)
	assert.Equal(t, snapshotID, resp.SnapshotId, "Snapshot id didn't match")
}

func TestCheckRepositoryReadiness_NoEventReturnsNoEvent(t *testing.T) {
	repositoryID := makeRepositoryID()

	resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
		RepositoryId: repositoryID,
		EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
	})

	require.NoError(t, err, "CheckRepositoryReadiness should not error for a non-existent event")
	assert.True(t, resp.Ready, "should be ready when no event exists")
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_NO_EVENT, resp.Reason, "reason should be NO_EVENT")
	assert.Nil(t, resp.MostRecentEvent, "MostRecentEvent should be nil when no event exists")
}

func TestCheckRepositoryReadiness_Pending(t *testing.T) {
	repositoryID := makeRepositoryID()
	ref := "refs/heads/main"
	sha := "faa40ef14cb556bafe62a84392896cd2af59b3bf"

	eventSvc := newDependabotEventService(t)
	_, err := eventSvc.RecordDependabotEvent(context.Background(), repositoryID, interfaces.EventTypePush, ref, sha, nil, []interfaces.DependabotRequestedSnapshot{
		{Ecosystem: "npm", ManifestPath: ".", Deadline: time.Now().Add(1 * time.Hour)},
		{Ecosystem: "golang", ManifestPath: ".", Deadline: time.Now().Add(1 * time.Hour)},
	})
	require.NoError(t, err)

	resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
		RepositoryId: repositoryID,
		EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
	})

	require.NoError(t, err)
	assert.False(t, resp.Ready, "should not be ready when snapshots are pending")
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_PENDING, resp.Reason, "reason should be PENDING")
	require.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
	assert.Equal(t, entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH, resp.MostRecentEvent.EventType, "event type should be PUSH")
	assert.Equal(t, ref, resp.MostRecentEvent.Ref, "ref should match the recorded event")
	assert.Equal(t, sha, resp.MostRecentEvent.Sha, "sha should match the recorded event")
	assert.NotNil(t, resp.MostRecentEvent.CreatedAt, "created_at should be populated")
}

func TestCheckRepositoryReadiness_Ready(t *testing.T) {
	repositoryID := makeRepositoryID()
	ref := "refs/heads/main"
	sha := "faa40ef14cb556bafe62a84392896cd2af59b3bf"

	eventSvc := newDependabotEventService(t)
	eventID, err := eventSvc.RecordDependabotEvent(context.Background(), repositoryID, interfaces.EventTypePush, ref, sha, nil, []interfaces.DependabotRequestedSnapshot{
		{Ecosystem: "npm", ManifestPath: ".", Deadline: time.Now().Add(1 * time.Hour)},
	})
	require.NoError(t, err)

	// Mark the snapshot as received
	_, err = eventSvc.MarkSnapshotReceived(context.Background(), eventID, 12345, ecosystems.NPM, ".")
	require.NoError(t, err)

	resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
		RepositoryId: repositoryID,
		EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
	})

	require.NoError(t, err)
	assert.True(t, resp.Ready, "should be ready when all snapshots are received")
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE, resp.Reason, "reason should be SNAPSHOT_COMPLETE")
	require.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
	assert.Equal(t, entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH, resp.MostRecentEvent.EventType, "event type should be PUSH")
	assert.Equal(t, ref, resp.MostRecentEvent.Ref, "ref should match the recorded event")
	assert.Equal(t, sha, resp.MostRecentEvent.Sha, "sha should match the recorded event")
	assert.NotNil(t, resp.MostRecentEvent.CreatedAt, "created_at should be populated")
}

func TestCheckRepositoryReadiness_EventFiltering(t *testing.T) {
	repositoryID := makeRepositoryID()
	ref := "refs/heads/main"
	initSHA := "aaa0000000000000000000000000000000000000"
	pushSHA := "bbb0000000000000000000000000000000000000"

	eventSvc := newDependabotEventService(t)

	// Record an init event and mark it complete
	initEventID, err := eventSvc.RecordDependabotEvent(context.Background(), repositoryID, interfaces.EventTypeInit, ref, initSHA, nil, []interfaces.DependabotRequestedSnapshot{
		{Ecosystem: "npm", ManifestPath: ".", Deadline: time.Now().Add(1 * time.Hour)},
	})
	require.NoError(t, err)
	_, err = eventSvc.MarkSnapshotReceived(context.Background(), initEventID, 11111, ecosystems.NPM, ".")
	require.NoError(t, err)

	// Record a push event (newer, by auto-increment ID) and mark it complete
	pushEventID, err := eventSvc.RecordDependabotEvent(context.Background(), repositoryID, interfaces.EventTypePush, ref, pushSHA, nil, []interfaces.DependabotRequestedSnapshot{
		{Ecosystem: "golang", ManifestPath: ".", Deadline: time.Now().Add(1 * time.Hour)},
	})
	require.NoError(t, err)
	_, err = eventSvc.MarkSnapshotReceived(context.Background(), pushEventID, 22222, ecosystems.Golang, ".")
	require.NoError(t, err)

	t.Run("no filter returns newest event", func(t *testing.T) {
		resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
			RepositoryId: repositoryID,
		})

		require.NoError(t, err)
		assert.True(t, resp.Ready, "should be ready when all snapshots are received")
		assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE, resp.Reason, "reason should be SNAPSHOT_COMPLETE")
		require.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
		assert.Equal(t, entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH, resp.MostRecentEvent.EventType, "should return the newest event (push)")
		assert.Equal(t, pushSHA, resp.MostRecentEvent.Sha, "sha should match the push event")
		assert.Equal(t, ref, resp.MostRecentEvent.Ref, "ref should match the push event")
		assert.NotNil(t, resp.MostRecentEvent.CreatedAt, "created_at should be populated")
	})

	t.Run("filtered to push returns the push event", func(t *testing.T) {
		resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
			RepositoryId: repositoryID,
			EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH,
		})

		require.NoError(t, err)
		assert.True(t, resp.Ready, "should be ready when all push snapshots are received")
		assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE, resp.Reason, "reason should be SNAPSHOT_COMPLETE")
		require.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
		assert.Equal(t, entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH, resp.MostRecentEvent.EventType, "event type should be PUSH")
		assert.Equal(t, pushSHA, resp.MostRecentEvent.Sha, "sha should match the push event")
		assert.Equal(t, ref, resp.MostRecentEvent.Ref, "ref should match the push event")
	})

	t.Run("filtered to init returns the init event", func(t *testing.T) {
		resp, err := dependabotClient.CheckRepositoryReadiness(context.Background(), &proto.CheckRepositoryReadinessRequest{
			RepositoryId: repositoryID,
			EventType:    entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT,
		})

		require.NoError(t, err)
		assert.True(t, resp.Ready, "should be ready when all init snapshots are received")
		assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE, resp.Reason, "reason should be SNAPSHOT_COMPLETE")
		require.NotNil(t, resp.MostRecentEvent, "MostRecentEvent should be populated")
		assert.Equal(t, entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT, resp.MostRecentEvent.EventType, "event type should be INIT")
		assert.Equal(t, initSHA, resp.MostRecentEvent.Sha, "sha should match the init event")
		assert.Equal(t, ref, resp.MostRecentEvent.Ref, "ref should match the init event")
	})
}

func TestCreateDependabotSnapshot_MarkAsReceived(t *testing.T) {
	repositoryID := makeRepositoryID()
	ref := "refs/heads/main"
	sha := "d329eee48e3b5042bb1c8b9b90268bd7dedf4678"

	// Seed an event with a requested snapshot for npm at the root directory
	eventSvc := newDependabotEventService(t)
	eventID, err := eventSvc.RecordDependabotEvent(context.Background(), repositoryID, interfaces.EventTypePush, ref, sha, nil, []interfaces.DependabotRequestedSnapshot{
		{
			Ecosystem:    "npm",
			ManifestPath: ".",
			Deadline:     time.Now().Add(1 * time.Hour),
		},
	})
	require.NoError(t, err, "RecordDependabotEvent should not error")

	// Verify the event is pending before we submit the snapshot
	readinessResp, err := dependabotClient.CheckEventReadiness(context.Background(), &proto.CheckEventReadinessRequest{
		DependabotEventId: eventID,
	})
	require.NoError(t, err)
	assert.False(t, readinessResp.Ready, "should not be ready before snapshot is received")
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_PENDING, readinessResp.Reason, "reason should be PENDING")

	// Submit a snapshot that matches the seeded event
	req := &proto.CreateDependabotSnapshotRequest{
		RepositoryId: repositoryID,
		Payload: &entities.Snapshot{
			Version: 10,
			Job: &entities.Snapshot_Job{
				Id:         "0",
				Correlator: "mark-as-received-test",
			},
			Sha: sha,
			Ref: ref,
			Detector: &entities.Snapshot_Detector{
				Name:    "integration-test",
				Url:     "https://example.com",
				Version: "0.0.1",
			},
			Metadata: map[string]string{
				"event_id":              strconv.FormatUint(eventID, 10),
				"scanned_manifest_path": "npm::/",
			},
			Scanned: timestamppb.Now(),
			Manifests: map[string]*entities.Manifest{
				"package-lock.json": {
					Name: "package-lock.json",
					File: &entities.Manifest_File{
						SourceLocation: "package-lock.json",
					},
					Metadata: map[string]string{
						"ecosystem": "npm",
					},
					Resolved: map[string]*entities.Dependency{
						"lodash": {
							PackageUrl: "pkg:npm/lodash@4.17.21",
						},
					},
				},
			},
		},
	}
	_, err = dependabotClient.CreateDependabotSnapshot(context.Background(), req)
	require.NoError(t, err, "CreateDependabotSnapshot should not error")

	// Verify the event is now complete
	readinessResp, err = dependabotClient.CheckEventReadiness(context.Background(), &proto.CheckEventReadinessRequest{
		DependabotEventId: eventID,
	})
	require.NoError(t, err)
	assert.True(t, readinessResp.Ready, "should be ready after snapshot is received")
	assert.Equal(t, entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE, readinessResp.Reason, "reason should be SNAPSHOT_COMPLETE")
}

func TestInternalSnapshot(t *testing.T) {
	repositoryID := makeRepositoryID()

	snapshotID := createSnapshot(t, repositoryID, internalSnapshot)
	resp := getSnapshot(t, repositoryID, snapshotID)

	assert.Contains(t, string(resp.Payload), "\"internal\":true", "The returned snapshot does not appear to be internal")

	hasManifestsResponse := hasManifests(t, repositoryID)
	assert.False(t, hasManifestsResponse.HasManifests, "The HasManifests response should be false for internal snapshots")

	assert.JSONEq(t, internalSnapshot, string(resp.Payload), "The submitted snapshot didn't match the response from GetSnapshot")
	assert.Equal(t, repositoryID, resp.RepositoryId, "Requested repo id %d didn't match repo id %d in response", repositoryID, resp.RepositoryId)
	assert.Equal(t, snapshotID, resp.SnapshotId, "Snapshot id didn't match")

	depsWithoutInternal := getDependenciesForRepository(t, repositoryID)
	assert.Empty(t, depsWithoutInternal.Manifests, "Internal snapshot should not be returned by GetDependenciesForRepository")

	depsWithInternal := getDependenciesForRepositoryIncludingInternal(t, repositoryID)
	require.Lenf(t, depsWithInternal.Manifests, 1, "Internal snapshot should be returned by GetDependenciesForRepositoryWithInternal")
	assert.Equal(t,
		depsWithInternal.Manifests["package-lock.json"].FilePath,
		"package-lock.json",
	)
}

func TestCreateAndGetDeprecatedFieldsDependencySnapshot(t *testing.T) {
	repositoryID := makeRepositoryID()

	snapshotID := createSnapshot(t, repositoryID, snapshotDeprecated)
	resp := getSnapshot(t, repositoryID, snapshotID)

	assert.JSONEq(t, snapshot, string(resp.Payload), "The submitted snapshot didn't match the response from GetSnapshot")
	assert.Equal(t, repositoryID, resp.RepositoryId, "Requested repo id %d didn't match repo id %d in response", repositoryID, resp.RepositoryId)
	assert.Equal(t, snapshotID, resp.SnapshotId, "Snapshot id didn't match")
}

func TestGetDependenciesForRepository(t *testing.T) {
	repositoryID := makeRepositoryID()

	// secondSnapshot is much like `snapshot`, but with slightly different dependencies.
	// we should see these merged with the dependencies from `snapshot`
	secondSnapshot := `{
  "version": 0,
  "sha": "b329eee48e3b5042bb1c8b9b90268bd7dedf4678",
  "ref": "refs/heads/main",
  "job": {
    "name": "second build",
    "id": "0"
  },
  "detector": {
	  "name": "integration tests (ruby)",
	  "url": "github/com/github/dependency-snapshots-api/detector",
	  "version": "0.0.1"
  },
  "scanned": "2021-12-13T20:26:00Z",
  "manifests": {
    "Gemfile.lock": {
      "name": "Gemfile.lock",
      "file": {
        "source_location": "Gemfile.lock"
      },
      "resolved": {
        "rails": {
          "purl": "pkg:gem/rails@4.2.0",
          "dependencies": []
        },
        "nokogiri": {
          "purl": "pkg:gem/nokogiri@5.5.5",
          "dependencies": []
        }
      }
    },
    "package-lock.json": {
      "name": "package-lock.json",
      "file": {
        "source_location": "package-lock.json"
      },
      "resolved": {
        "react": {
          "package_url": "pkg:npm/react@1.2.3"
        }
      }
    }
  }
}`
	createSnapshot(t, repositoryID, snapshot)
	createSnapshot(t, repositoryID, secondSnapshot)
	resp := getDependenciesForRepository(t, repositoryID)

	require.Contains(t, resp.Manifests, "package-lock.json")
	assert.Contains(t, resp.Manifests["package-lock.json"].Dependencies, "@actions/core")
	assert.Contains(t, resp.Manifests["package-lock.json"].Dependencies, "@actions/http-client")
	assert.Contains(t, resp.Manifests["package-lock.json"].Dependencies, "tunnel")
	assert.NotContains(t, resp.Manifests["package-lock.json"].Dependencies, "react", "should not contain react as we do not combine manifests if different detectors")

	require.Contains(t, resp.Manifests, "Gemfile.lock")
	assert.Contains(t, resp.Manifests["Gemfile.lock"].Dependencies, "rails")
	assert.Contains(t, resp.Manifests["Gemfile.lock"].Dependencies, "nokogiri")
}

func TestDiff(t *testing.T) {
	if os.Getenv("ENTERPRISE") == "true" {
		// We need historical snapshot storage to make this work,
		// which is not available in enterprise
		return
	}
	repositoryID := makeRepositoryID()

	oldCommit := mockGitCommits[3]
	newCommit := mockGitCommits[1]

	oldA := BasicSnapshot(oldCommit).SetDetector("javascript")
	oldA.AddJquery("1.0.0")
	oldA.Submit(t, repositoryID)
	oldASnapMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
		SnapshotId: oldA.ID,
		Correlator: oldA.Job["correlator"],
		Detector:   oldA.Detector["name"],
	}

	oldB := BasicSnapshot(oldCommit).SetDetector("ruby")
	oldB.AddRails("4.0.0")
	oldB.AddRails("5.0.0")
	oldB.Submit(t, repositoryID)
	oldBSnapMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
		SnapshotId: oldB.ID,
		Correlator: oldB.Job["correlator"],
		Detector:   oldB.Detector["name"],
	}

	oldC := BasicSnapshot(oldCommit).SetDetector("java")
	oldC.AddLog4j("3.1.0")
	oldC.Submit(t, repositoryID)
	oldCSnapMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
		SnapshotId: oldC.ID,
		Correlator: oldC.Job["correlator"],
		Detector:   oldC.Detector["name"],
	}

	newA := BasicSnapshot(newCommit).SetDetector("javascript")
	newA.AddJquery("2.0.0")
	newA.AddDep("package-lock.json", "npm", "jquery", "3.0.0", "development")
	newA.Submit(t, repositoryID)
	newASnapMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
		SnapshotId: newA.ID,
		Correlator: newA.Job["correlator"],
		Detector:   newA.Detector["name"],
	}

	newB := BasicSnapshot(newCommit).SetDetector("ruby")
	newB.AddRails("5.0.0")
	newB.Submit(t, repositoryID)

	// The diff should include:
	// REMOVE jquery 1.0.0
	// ADD    jquery 2.0.0
	// ADD    jquery 3.0.0 (dev dependency)
	// REMOVE log4j  3.1.0
	// REMOVE rails  4.0.0
	resp := getDiff(t, repositoryID, oldCommit, newCommit)
	changes := resp.GetDependencyChanges()
	require.Lenf(t, changes, 5, "Expected 5 dependency changes, got %d", len(resp.DependencyChanges))
	assert.Equal(t, uint32(3), resp.BaseSnapshotsCompared)
	assert.Equal(t, uint32(2), resp.HeadSnapshotsCompared)

	sort.Slice(changes, func(i, j int) bool {
		return changes[i].Version < changes[j].Version
	})

	// First up should be the jquery 1.0.0 removal
	assert.Equal(t, "jquery", changes[0].Name, "Expected jquery, got %s", changes[0].Name)
	assert.Equal(t, "1.0.0", changes[0].Version)
	assert.Equal(t, "REMOVED", changes[0].ChangeType.String())
	assert.Equal(t, "RUNTIME", changes[0].Scope.String())
	assert.Equal(t, oldASnapMeta, changes[0].SnapshotMetadata)

	// Next up should be the jquery 2.0.0 addition
	assert.Equal(t, "jquery", changes[1].Name, "Expected jquery, got %s", changes[1].Name)
	assert.Equal(t, "2.0.0", changes[1].Version)
	assert.Equal(t, "ADDED", changes[1].ChangeType.String())
	assert.Equal(t, "RUNTIME", changes[1].Scope.String())
	assert.Equal(t, newASnapMeta, changes[1].SnapshotMetadata)

	// Then the jquery 3.0.0 (dev) addition
	assert.Equal(t, "jquery", changes[2].Name, "Expected jquery, got %s", changes[1].Name)
	assert.Equal(t, "3.0.0", changes[2].Version)
	assert.Equal(t, "ADDED", changes[2].ChangeType.String())
	assert.Equal(t, "DEVELOPMENT", changes[2].Scope.String())
	assert.Equal(t, newASnapMeta, changes[2].SnapshotMetadata)

	// Then the log4j 3.1.0 removal
	assert.Equal(t, "log4j", changes[3].Name, "Expected log4j, got %s", changes[2].Name)
	assert.Equal(t, "3.1.0", changes[3].Version)
	assert.Equal(t, "REMOVED", changes[3].ChangeType.String())
	assert.Equal(t, "RUNTIME", changes[3].Scope.String())
	assert.Equal(t, oldCSnapMeta, changes[3].SnapshotMetadata)

	// Finally the rails 4.0.0 removal
	assert.Equal(t, "rails", changes[4].Name, "Expected rails, got %s", changes[3].Name)
	assert.Equal(t, "4.0.0", changes[4].Version)
	assert.Equal(t, "REMOVED", changes[4].ChangeType.String())
	assert.Equal(t, "RUNTIME", changes[4].Scope.String())
	assert.Equal(t, oldBSnapMeta, changes[4].SnapshotMetadata)
}

func TestDiffWithEmptyTarget(t *testing.T) {
	if os.Getenv("ENTERPRISE") == "true" {
		// We need historical snapshot storage to make this work,
		// which is not available in enterprise
		return
	}

	repositoryID := makeRepositoryID()

	baseSHA := mockGitCommits[3]
	targetSHA := mockGitCommits[1]

	baseSnap := BasicSnapshot(baseSHA).SetDetector("javascript")
	baseSnap.AddJquery("1.0.0")
	baseSnap.Submit(t, repositoryID)

	resp, err := getDiffOrError(t, repositoryID, baseSHA, targetSHA)
	assert.Nil(t, resp)
	assert.ErrorContains(t, err, "no snapshots found for head commit")
	expectedMetaMap := map[string]string{
		"base_snapshots": "1",
	}
	if twerr, ok := err.(twirp.Error); ok {
		assert.Equal(t, expectedMetaMap, twerr.MetaMap())
	} else {
		t.Error("Expected twirp error")
	}
}

func TestDiffWithNoManifests(t *testing.T) {
	if os.Getenv("ENTERPRISE") == "true" {
		// We need historical snapshot storage to make this work,
		// which is not available in enterprise
		return
	}

	repositoryID := makeRepositoryID() + 1

	baseSHA := mockGitCommits[3]
	targetSHA := mockGitCommits[1]

	resp, err := getDiffOrError(t, repositoryID, baseSHA, targetSHA)
	assert.Nil(t, resp)
	assert.ErrorContains(t, err, "no snapshots found")
	expectedMetaMap := map[string]string{
		"base_snapshots": "0",
	}
	if twerr, ok := err.(twirp.Error); ok {
		assert.Equal(t, expectedMetaMap, twerr.MetaMap())
	} else {
		t.Error("Expected twirp error")
	}
}

func TestDiffWithEmptyBase(t *testing.T) {
	if os.Getenv("ENTERPRISE") == "true" {
		// We need historical snapshot storage to make this work,
		// which is not available in enterprise
		return
	}

	repositoryID := makeRepositoryID()

	baseSHA := mockGitCommits[3]
	targetSHA := mockGitCommits[1]

	targetSnap := BasicSnapshot(targetSHA).SetDetector("javascript")
	targetSnap.AddJquery("1.0.0")
	targetSnap.AddLog4j("3.1.0")
	targetSnap.Submit(t, repositoryID)

	snapMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
		SnapshotId: targetSnap.ID,
		Correlator: targetSnap.Job["correlator"],
		Detector:   targetSnap.Detector["name"],
	}

	hasManifestsResp := hasManifests(t, repositoryID)
	assert.Truef(t, hasManifestsResp.HasManifests, "Expected repository %d to have manifests (precondition for test)", repositoryID)

	resp := getDiff(t, repositoryID, baseSHA, targetSHA)
	changes := resp.GetDependencyChanges()
	require.Lenf(t, changes, 2, "Expected 2 dependency change, got %d", len(resp.DependencyChanges))
	assert.Equalf(t, uint32(0), resp.BaseSnapshotsCompared, "Expected 0 base snapshots compared, got %d", resp.BaseSnapshotsCompared)
	assert.Equalf(t, uint32(1), resp.HeadSnapshotsCompared, "Expected 1 head snapshots compared, got %d", resp.HeadSnapshotsCompared)

	// put the results in order to make comparison easier
	sort.Slice(changes, func(i, j int) bool {
		return changes[i].Version < changes[j].Version
	})

	// First up should be the jquery 1.0.0 addition
	assert.Equal(t, "jquery", changes[0].Name, "Expected jquery, got %s", changes[0].Name)
	assert.Equal(t, "1.0.0", changes[0].Version)
	assert.Equal(t, "ADDED", changes[0].ChangeType.String())
	assert.Equal(t, snapMeta, changes[0].SnapshotMetadata)

	// Then the log4j 3.1.0 addition
	assert.Equal(t, "log4j", changes[1].Name, "Expected log4j, got %s", changes[1].Name)
	assert.Equal(t, "3.1.0", changes[1].Version)
	assert.Equal(t, "ADDED", changes[1].ChangeType.String())
	assert.Equal(t, snapMeta, changes[1].SnapshotMetadata)
}

func TestHasManifests(t *testing.T) {
	repositoryID := makeRepositoryID()
	createSnapshot(t, repositoryID, snapshot)

	resp := hasManifests(t, repositoryID)
	assert.True(t, resp.HasManifests, "expected repository to have manifests")
}

func TestRepositoriesContainingDependencies(t *testing.T) {
	repositoryID := makeRepositoryID()
	createSnapshot(t, repositoryID, snapshot)

	resp := repositoriesContainingDependency(t, "pkg:npm/%40actions/core", "=1.1.9")
	assert.NotEmpty(t, resp.RepositoryIds)
	assert.Contains(t, resp.RepositoryIds, repositoryID)
}

func TestGetDependenciesForRepositoryEmpty(t *testing.T) {
	repositoryID := makeRepositoryID()

	resp := getDependenciesForRepository(t, repositoryID)
	assert.Empty(t, resp.Manifests, "expected no manifests")
}

func TestRepositoriesContainingDependenciesNegative(t *testing.T) {
	repositoryID := makeRepositoryID()
	createSnapshot(t, repositoryID, snapshot)

	resp := repositoriesContainingDependency(t, "pkg:npm/%40actions/core", ">9.9.9")
	assert.Empty(t, resp.RepositoryIds)
	assert.NotContains(t, resp.RepositoryIds, repositoryID)
}

// TestSubmitNonCanonical checks that we can submit a snapshot for a non-canonical branch/sha:
//  1. successfully
//  2. it will not update the canonical dependencies
func TestSubmittingNonCanonical(t *testing.T) {
	repositoryID := makeRepositoryID()
	snapshotNonMain := strings.Replace(snapshot, "refs/heads/main", "refs/heads/blorg", 1)
	snapshotNonMain = strings.Replace(snapshotNonMain, "d329eee48e3b5042bb1c8b9b90268bd7dedf4678", "fakeshanottobefound", 1)

	resp := hasManifests(t, repositoryID)
	assert.False(t, resp.HasManifests, "expected repository to not have manifests")

	id := createSnapshot(t, repositoryID, snapshotNonMain)
	if os.Getenv("ENTERPRISE") != "true" {
		snapAsReceived := getSnapshot(t, repositoryID, id)
		assert.JSONEq(t, snapshotNonMain, string(snapAsReceived.Payload), "The submitted snapshot didn't match the response from GetSnapshot")
	} else {
		require.Equal(t, id, uint64(0))
	}

	deps := getDependenciesForRepository(t, repositoryID)
	assert.Empty(t, deps.Manifests, "expected no manifests, found %v", deps.Manifests)
}

func TestSubmittingInvalidPurl(t *testing.T) {
	repositoryID := makeRepositoryID()
	req := &proto.CreateDependencySnapshotRequest{
		RepositoryId: repositoryID,
		Payload:      []byte(snapshotWithBadPurl),
	}
	_, err := snapshotsClient.CreateDependencySnapshot(context.Background(), req)
	require.Error(t, err)
	assert.Equal(t, twirp.Malformed, err.(twirp.Error).Code())
	assert.ErrorContains(t, err, "twirp error malformed: invalid package url: in manifest \"package-lock.json\" decoding \"/npm/%40actions/core@1.1.9\"")
}

func TestSubmittingInvalidPurlType(t *testing.T) {
	repositoryID := makeRepositoryID()
	req := &proto.CreateDependencySnapshotRequest{
		RepositoryId: repositoryID,
		Payload:      []byte(snapshotWithBadPurlType),
	}
	_, err := snapshotsClient.CreateDependencySnapshot(context.Background(), req)
	require.Error(t, err)
	assert.Equal(t, twirp.Malformed, err.(twirp.Error).Code())
	assert.ErrorContains(t, err, "twirp error malformed: invalid package url: in manifest \"package-lock.json\" decoding \"pkg:blorgle/%40actions/core@1.1.9\": invalid package url type: blorgle")
}

func TestGetIncludedSnapshots(t *testing.T) {
	repositoryID := makeRepositoryID()
	createSnapshot(t, repositoryID, snapshot)

	resp := getIncludedSnapshotsForRepository(t, repositoryID)
	require.True(t, len(resp.IncludedSnapshots) == 1)
}

func TestExcludeSnapshots(t *testing.T) {
	repositoryID := makeRepositoryID()
	createSnapshot(t, repositoryID, snapshot)

	resp := getIncludedSnapshotsForRepository(t, repositoryID)
	require.True(t, len(resp.IncludedSnapshots) == 1)

	excludeResp := excludeSnapshotsFromRepository(t, repositoryID, []uint64{resp.IncludedSnapshots[0].SnapshotId})
	require.ElementsMatch(t, []uint64{resp.IncludedSnapshots[0].SnapshotId}, excludeResp.ExcludedSnapshotIds)

	resp = getIncludedSnapshotsForRepository(t, repositoryID)
	require.True(t, len(resp.IncludedSnapshots) == 0)
}

// -- Test helper functions

// makeRepositoryID returns a random uint64 in the range of non-negative int32 values.
// This is because although the proto interface advertises uint64 ids, the
// underlying database schema throughout github stores repository ids as signed
// 32 bit integers
func makeRepositoryID() uint64 {
	// Use a new source for each call to makeRepositoryID to avoid collisions
	rand := rand.New(rand.NewSource(time.Now().UnixNano()))
	return uint64(rand.Int31())
}

// createSnapshot creates a snapshot and returns the snapshot id. This fails the test if there is an error.
func createSnapshot(t *testing.T, repositoryID uint64, snapshot string) uint64 {
	t.Helper()
	req := &proto.CreateDependencySnapshotRequest{
		RepositoryId: repositoryID,
		Payload:      []byte(snapshot),
	}
	resp, err := snapshotsClient.CreateDependencySnapshot(context.Background(), req)
	require.NoError(t, err, "Could not create snapshot")
	return resp.SnapshotId
}

// createDependabotSnapshot creates a dependabot snapshot and returns the snapshot id. This fails the test if there is an error.
func createDependabotSnapshot(t *testing.T, repositoryID uint64, req *proto.CreateDependabotSnapshotRequest) uint64 {
	t.Helper()

	req.RepositoryId = repositoryID
	resp, err := dependabotClient.CreateDependabotSnapshot(context.Background(), req)
	require.NoError(t, err, "Could not create dependabot snapshot")
	return resp.SnapshotId
}

// getSnapshot retrieves a snapshot. This fails the test if there is an error.
func getSnapshot(t *testing.T, repositoryID uint64, snapshotID uint64) *proto.GetDependencySnapshotResponse {
	t.Helper()
	req := &proto.GetDependencySnapshotRequest{
		RepositoryId: repositoryID,
		SnapshotId:   snapshotID,
	}
	resp, err := snapshotsClient.GetDependencySnapshot(context.Background(), req)
	require.NoError(t, err, "Could not retrieve snapshot")
	return resp
}

func getDependenciesForRepository(t *testing.T, repositoryID uint64) *proto.GetDependenciesForRepositoryResponse {
	t.Helper()

	req := &proto.GetDependenciesForRepositoryRequest{
		RepositoryId: repositoryID,
	}
	resp, err := dependenciesClient.GetDependenciesForRepository(context.Background(), req)
	require.NoError(t, err, "Could not retrieve dependencies for repository %v", repositoryID)
	return resp
}

func getDependenciesForRepositoryIncludingInternal(t *testing.T, repositoryID uint64) *proto.GetDependenciesForRepositoryResponse {
	t.Helper()

	req := &proto.GetDependenciesForRepositoryRequest{
		RepositoryId:             repositoryID,
		IncludeInternalSnapshots: true,
	}
	resp, err := dependenciesClient.GetDependenciesForRepository(context.Background(), req)
	require.NoError(t, err, "Could not retrieve dependencies for repository %v", repositoryID)
	return resp
}

func hasManifests(t *testing.T, repositoryID uint64) *proto.HasManifestsResponse {
	t.Helper()

	req := &proto.HasManifestsRequest{
		RepositoryId: repositoryID,
	}

	resp, err := dependenciesClient.HasManifests(context.Background(), req)
	require.NoError(t, err, "Failed to get for has manifests")
	return resp
}

func getIncludedSnapshotsForRepository(t *testing.T, repositoryID uint64) *proto.GetIncludedDependencySnapshotsResponse {
	t.Helper()

	req := &proto.GetIncludedDependencySnapshotsRequest{
		RepositoryId: repositoryID,
	}

	resp, err := snapshotsClient.GetIncludedDependencySnapshots(context.Background(), req)
	require.NoError(t, err, "Failed to get included snapshots")
	return resp
}

func excludeSnapshotsFromRepository(t *testing.T, repositoryID uint64, snapshotIDs []uint64) *proto.ExcludeDependencySnapshotsResponse {
	t.Helper()

	req := &proto.ExcludeDependencySnapshotsRequest{
		RepositoryId: repositoryID,
		SnapshotIds:  snapshotIDs,
	}

	resp, err := snapshotsClient.ExcludeDependencySnapshots(context.Background(), req)
	require.NoError(t, err, "Failed to exclude snapshots")
	return resp
}

func repositoriesContainingDependency(t *testing.T, purl, versionRange string) *proto.RepositoriesContainingDependencyResponse {
	t.Helper()

	req := &proto.RepositoriesContainingDependencyRequest{
		BasePurl:     purl,
		VersionRange: versionRange,
	}

	resp, err := dependenciesClient.RepositoriesContainingDependency(context.Background(), req)
	require.NoError(t, err, "Failed to get repositories for purl %s and version range %s", purl, versionRange)
	return resp
}

func getDiffOrError(t *testing.T, repositoryID uint64, baseSHA, targetSHA string) (*proto.GetSnapshotDiffResponse, error) {
	t.Helper()

	req := &proto.GetSnapshotDiffRequest{
		RepositoryId: repositoryID,
		Basehead:     fmt.Sprintf("%s...%s", baseSHA, targetSHA),
	}

	return snapshotsClient.GetSnapshotDiff(context.Background(), req)
}

func getDiff(t *testing.T, repositoryID uint64, baseSHA, targetSHA string) *proto.GetSnapshotDiffResponse {
	t.Helper()

	resp, err := getDiffOrError(t, repositoryID, baseSHA, targetSHA)
	require.NoError(t, err, "Failed to get diff for repository %v", repositoryID)
	return resp
}

// objectSvc is a local mock for the spokes ObjectsAPI
type objectSvc struct{ objects.ObjectsAPI }

func (o *objectSvc) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	return &objects.ResolveObjectResponse{
		Oid: types.NewObjectID("b1c28a3578b50d640718b6400bb7a25b981944b4"),
	}, nil
}

type referencesSvc struct{ references.ReferencesAPI }

func (r *referencesSvc) GetDefaultBranch(context.Context, *references.GetDefaultBranchRequest) (*references.GetDefaultBranchResponse, error) {
	return &references.GetDefaultBranchResponse{Reference: &types.Reference{Name: []byte("refs/heads/main")}}, nil
}

type commitsSvc struct{ commits.CommitsAPI }

// Commits SHAs are in order from most recent to oldest
var mockGitCommits = []string{
	"e329eee48e3b5042bb1c8b9b90268bd7dedf4678",
	"d329eee48e3b5042bb1c8b9b90268bd7dedf4678",
	"c329eee48e3b5042bb1c8b9b90268bd7dedf4678",
	"b329eee48e3b5042bb1c8b9b90268bd7dedf4678",
	"a329eee48e3b5042bb1c8b9b90268bd7dedf4678",
}

func (c *commitsSvc) ListCommits(context.Context, *commits.ListCommitsRequest) (*commits.ListCommitsResponse, error) {
	commit := func(oid string) *commits.CommitItem {
		return &commits.CommitItem{
			Oid: &types.ObjectID{
				Id: oid,
			},
		}
	}

	commitsToReturn := make([]*commits.CommitItem, len(mockGitCommits))
	for i, oid := range mockGitCommits {
		commitsToReturn[i] = commit(oid)
	}

	return &commits.ListCommitsResponse{
		Commits: commitsToReturn,
	}, nil
}

// serveSpokes serves the mock spokes API on the network
func serveSpokes() {
	spokesHandler := http.NewServeMux()
	spokesHandler.Handle(objects.ObjectsAPIPathPrefix, objects.NewObjectsAPIServer(&objectSvc{}))
	spokesHandler.Handle(references.ReferencesAPIPathPrefix, references.NewReferencesAPIServer(&referencesSvc{}))
	spokesHandler.Handle(commits.CommitsAPIPathPrefix, commits.NewCommitsAPIServer(&commitsSvc{}))
	serve(":28081", spokesHandler)
}

func serve(addr string, handler http.Handler) {
	go func() {
		if err := http.ListenAndServe(addr, handler); err != nil {
			log.Fatal(err)
		}
	}()
}

// newDependabotEventService creates a DependabotEventService connected to the test database.
func newDependabotEventService(t *testing.T) interfaces.DependabotEventService {
	t.Helper()

	cfg, err := config.Load("")
	require.NoError(t, err, "could not load config")

	sqlDB, err := db.ConnectToMysql(context.Background(), cfg.NewReadWriteMysqlConfig(), 2, 2)
	require.NoError(t, err, "could not connect to MySQL")
	t.Cleanup(func() { sqlDB.Close() })

	sqlxDB, err := db.NewSqlxDatabase(sqlDB)
	require.NoError(t, err, "could not create sqlx database")

	adapter := storage.NewAdapter(storage.AdapterOptions{
		DB:      sqlxDB,
		Statter: stats.NullStatter,
	})
	return dependabot.NewEventService(adapter, stats.NullStatter)
}

type Snapshot struct {
	ID        uint64              `json:"id"`
	Version   int                 `json:"version"`
	Sha       string              `json:"sha"`
	Internal  bool                `json:"internal,omitempty"`
	Ref       string              `json:"ref"`
	Job       map[string]string   `json:"job"`
	Detector  map[string]string   `json:"detector"`
	Scanned   string              `json:"scanned"`
	Manifests map[string]Manifest `json:"manifests"`
}

type Manifest struct {
	Name     string                    `json:"name"`
	File     map[string]string         `json:"file"`
	Resolved map[string]DependencyNode `json:"resolved"`
}

type DependencyNode struct {
	Purl         string   `json:"purl"`
	Scope        string   `json:"scope"`
	Dependencies []string `json:"dependencies"`
}

func BasicSnapshot(sha string) *Snapshot {
	return &Snapshot{
		Version: 0,
		Sha:     sha,
		Ref:     "refs/heads/main",
		Job: map[string]string{
			"name":       "integration tests",
			"correlator": "integration test correlator",
			"id":         "0",
		},
		Detector: map[string]string{
			"name":    "integration tests (helper)",
			"url":     "http://example.com",
			"version": "1.0.0",
		},
		Scanned:   time.Now().Format(time.RFC3339),
		Manifests: map[string]Manifest{},
	}
}

func (s *Snapshot) AddDep(manifestPath, ecosystem, name, version, scope string) *Snapshot {
	if _, ok := s.Manifests[manifestPath]; !ok {
		s.Manifests[manifestPath] = Manifest{
			Name:     manifestPath,
			File:     map[string]string{"source_location": manifestPath},
			Resolved: map[string]DependencyNode{},
		}
	}
	purl := fmt.Sprintf("pkg:%s/%s@%s", ecosystem, name, version)
	s.Manifests[manifestPath].Resolved[purl] = DependencyNode{
		Purl:         purl,
		Dependencies: []string{},
		Scope:        scope,
	}
	return s
}

func (s *Snapshot) AddJquery(version string) *Snapshot {
	return s.AddDep("package-lock.json", "npm", "jquery", version, "runtime")
}

func (s *Snapshot) AddRails(version string) *Snapshot {
	return s.AddDep("Gemfile.lock", "gem", "rails", version, "runtime")
}

func (s *Snapshot) AddLog4j(version string) *Snapshot {
	return s.AddDep("pom.xml", "maven", "log4j", version, "runtime")
}

func (s *Snapshot) SetDetector(name string) *Snapshot {
	s.Detector["name"] = name
	return s
}

func (s *Snapshot) SetAge(seconds int) *Snapshot {
	newTime := time.Now().Add(-time.Duration(seconds) * time.Second)
	s.Scanned = newTime.Format(time.RFC3339)
	return s
}

func (s *Snapshot) Submit(t *testing.T, repositoryID uint64) uint64 {
	t.Helper()
	jsonb, err := json.Marshal(s)
	require.NoError(t, err)

	id := createSnapshot(t, repositoryID, string(jsonb))
	s.ID = id
	return id
}
