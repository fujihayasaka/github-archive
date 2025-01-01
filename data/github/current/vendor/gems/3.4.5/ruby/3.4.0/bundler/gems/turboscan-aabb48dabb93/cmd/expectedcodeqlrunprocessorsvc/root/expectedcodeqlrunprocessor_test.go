package root

import (
	"testing"
	"time"

	hydrolib "github.com/github/hydro-client-go/v7/pkg/hydro"
	cshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// TestPublish publishes a message to the ManagedAnalysesExpecteCodeqlRun topic which is then consumed
// by the locally running binary (either in debug mode or as an unmonitored process.) You would need to
// remove the t.Skip() for this test to run.
func TestPublish(t *testing.T) {
	t.Skip()
	cfg, err := config.Load()
	require.NoError(t, err, "failed to retrieve configs")
	logger, err := cfg.NewLogger()
	require.NoError(t, err, "failed to build a logger")
	sc := cfg.NewStatsClient("testing")
	kc, err := cfg.NewKafkaConfig(logger, nil)
	require.NoError(t, err, "failed to get kafka configurations")
	sink, err := hydrolib.NewKafkaSink(*kc)
	require.NoError(t, err, "failed to create kafka sink")
	publisher, err := hydrolib.NewPublisher(sink,
		hydrolib.WithTopicFormat(hydrolib.TopicFormatV2),
		hydrolib.WithPublisherStats(sc),
	)
	require.NoError(t, err, "failed to create a new publisher")
	msg := cshydro.ManagedAnalysesExpectedCodeqlRun{
		RepositoryId:        1,
		OwnerId:             1,
		TriggeringEventTime: timestamppb.New(time.Now().Add(-time.Minute)),
		TriggeringEventType: "pr",
		Ref:                 []byte("refs/heads/main"),
	}
	err = publisher.Publish(&msg, hydrolib.WithTopic(topics.ManagedAnalysesExpectedCodeqlRun))
	require.NoError(t, err, "failed to publish the message")
}
