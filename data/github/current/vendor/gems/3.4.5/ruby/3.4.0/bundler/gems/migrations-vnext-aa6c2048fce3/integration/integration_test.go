//go:build integrationtest

// Package integration contains integration tests that exercise the entire system
package integration

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/adapters/archive"
	"github.com/github/migrations-vnext/internal/pkg/assets"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/kafka"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/github/migrations-vnext/internal/pkg/resourceworker"
	"github.com/go-redis/redis/v8"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_OutOfOrderIntegration(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	logger := log.WithLevel(log.InfoLevel)
	statter := stats.NullStatter

	enterpriseID := randomInt(1_000_000, 1_000_000_000)
	namespace := fmt.Sprintf("enterprise:%d", enterpriseID)
	container := strings.ToLower(RandomString(10))

	// setup kafka
	addr := SetupKafkaLiteTest(t)
	eventTopic := RandomString(10)
	resourceTopic := RandomString(10)
	resourceConsumer := kafka.NewKafkaGoConsumer(addr, resourceTopic, "test-group", "", 2, logger)

	// create dummy importer
	importer := client.NewDummyImporter(logger)
	// set up the Redis options
	opts := &redis.Options{
		Addr:     DockerComposePort(t, "redis", 6379), // Redis server address
		Password: "",                                  // No password set
		DB:       0,                                   // Use default DB
	}

	// Run the preseed command for acme_widgets
	// TODO: move the preseed logic from the main package to a separate package
	//       so that we can call it directly and not shell out to the script
	logger.Info("running preseed-acme and preseed-acme-git")
	cmd := exec.Command("/bin/sh",
		"-c",
		fmt.Sprintf("cd %s/.. && NAMESPACE=%s ./script/preseed-acme && NAMESPACE=%s ./script/preseed-acme-git",
			GetCurrentDir(t), namespace, namespace))
	output, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, string(output))

	// Create a new Redis client
	c := redis.NewClient(opts)
	// Create KVResolver
	kv, err := resource.NewKVRedis(c, logger, statter)
	require.NoError(t, err)
	// Create DAG to process eligible nodes
	d, err := dag.NewRedisDAG(c, logger)
	require.NoError(t, err)

	// Use out-of-order loader to write the resources to Kafka
	azureAddr := "http://" + DockerComposePort(t, "azurite", 10000)

	// Create Store to store payloads
	absPayload, err := blobstore.NewStore(ctx, azureAddr, TestAccountName, TestAccountKey, container, logger)
	require.NoError(t, err)

	// Create loader
	loader := resource.NewLoaderImpl(
		resource.WithDAG(d),
		resource.WithKV(kv),
		resource.WithLogger(logger),
		resource.WithImportClient(importer),
		resource.WithIntermediateStore(absPayload),
		resource.WithEnterpriseID(int64(enterpriseID)),
		resource.WithUploader(assets.DummyUploadClient{}),
	)

	// Create dagWorker
	workerOpts := []resourceworker.Option{
		resourceworker.WithConsumer(resourceConsumer),
		resourceworker.WithLoader(loader),
		resourceworker.WithObjectStore(absPayload),
		resourceworker.WithLogger(logger),
		resourceworker.WithStatter(statter),
	}
	resourceWorker, err := resourceworker.New(workerOpts...)
	require.NoError(t, err)

	// Load resources from Kafka
	go func() { _ = resourceWorker.Run(ctx) }()

	// Create archive loader
	archiveLoader := archive.NewLoader(
		archive.WithRootPath(GetCurrentDir(t)+"/fixtures/acme-widgets"),
		archive.WithShuffleResources(true),
		archive.WithManager(dag.NewManager(d, absPayload, logger)),
		archive.WithMaxIssueEventsPerBatch(1),
		archive.WithLogger(logger),
		archive.WithEnterpriseID(int64(enterpriseID)),
		archive.WithDefaultUserID(1),
		archive.WithSASGenerator(absPayload),
	)
	// Load archive to DAG
	err = archiveLoader.ToDAG()
	require.NoError(t, err)

	// Create DAG worker
	eventProducer, err := kafka.NewKafkaGoProducer(addr, eventTopic, "", logger)
	require.NoError(t, err)
	resourceProducer, err := kafka.NewKafkaGoProducer(addr, resourceTopic, "", logger)
	require.NoError(t, err)
	dagWorker := dag.NewWorker(10, d, absPayload, eventProducer, resourceProducer, logger.WithFields(kvp.String("component", "dag-dagWorker")))

	// Run DAG worker to process eligible nodes
	go func() {
		_ = dagWorker.ProcessEligibleNodes(ctx, namespace)
	}()

	// as we are using out-of-order loader, we need to wait for all the resources to be loaded
	// before we can assert that the importer has the expected resources
	assert.Eventually(t, func() bool {
		nodes, err := d.EligibleNodes(ctx, namespace)
		require.NoError(t, err)
		return len(nodes) == 0
	}, time.Minute, 10*time.Second)

	// TODO: add more assertions about the actual content of the importer and not only its cardinality
	assert.Len(t, importer.Organizations, 1)
	assert.Len(t, importer.OrganizationSettings, 1)
	assert.Len(t, importer.Mannequins, 6)
	assert.Len(t, importer.Teams, 4)
	assert.Len(t, importer.Repositories, 1)
	assert.Len(t, importer.ProtectedBranches, 1)
	require.Len(t, importer.Issues, 6)
	assert.Len(t, importer.UpdateRepositoryReqs, 1)
	assert.Len(t, importer.UpdateActionsSettingsReqs, 1)
	assert.Len(t, importer.Comments, 7)
	assert.Len(t, importer.Reactions, 5)
	assert.Len(t, importer.Milestones, 1)
	assert.Len(t, importer.StoragePolicies, 5)
	require.Len(t, importer.TimeLineEvents, 56)
	require.Len(t, importer.RepositoryLabels, 1)
	assert.Len(t, importer.RepositoryLabels[0].Labels, 4)
	assert.Len(t, importer.PullRequests, 3)
	require.Len(t, importer.PullRequestReviews, 1)
	assert.Len(t, importer.Projects, 2)
	require.Len(t, importer.AddIssueLabels, 1)
	assert.Len(t, importer.CommitComments, 3)
	assert.Len(t, importer.ProjectColumns, 4)
	assert.Len(t, importer.ProjectCards, 4)
	assert.Len(t, importer.AddIssueLabels, 1)
	assert.Len(t, importer.CloseIssueReferences, 1)
	assert.Len(t, importer.Releases, 3)
	assert.Len(t, importer.ReleaseAssets, 2)

	// Check that base URL in issue 11 was transformed
	var body string
	for i := range importer.Issues {
		if importer.Issues[i].Number != 11 {
			continue
		}
		body = importer.Issues[i].Body
		break
	}
	require.NotEmptyf(t, body, "could not find issue 11")
	assert.Containsf(t, body, "http://github.localhost", "expected issue body to contain http://github.localhost, got %s", body)
}
