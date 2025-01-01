package hydro

import (
	"context"
	basicLogger "log"

	"math"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"

	"github.com/github/go-exceptions"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"

	v1 "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"

	"github.com/github/github-telemetry-go/log"
	hydro_pb "github.com/github/trust-metadata-api/hydro/schemas/github/trust_metadata_api/v0"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Client represents hydro client
type Client struct {
	publisher *hydro.Publisher
	msgChan   chan any
	logger    log.Logger
	reporter  *exceptions.Reporter
}

type Config struct {
	KafkaBrokers  []string
	KafkaClientID string
	KafkaRootCA   string
}

type CreateAttestationHydroMessage struct {
	bundle   *v1.Bundle
	ownerID  uint64
	repoID   uint64
	tenantID uint64
	fields   map[string]string
}

type GetAttestationHydroMessage struct {
	TenantID          uint64
	OwnerID           uint64
	RepositoryID      uint64
	ActorID           uint64
	InstallationID    uint64
	SSIITargetID      uint64
	SSIIRepositoryID  uint64
	PredicateType     string
	CreatedAt         time.Time
	RunnerEnvironment string
	RepoVisibility    string
	GitRef            string
	SubjectsCount     int
	fields            map[string]string
}

// NewHydroClient creates a new hydro client with a publisher
func NewHydroClient(config Config, logger log.Logger, reporter *exceptions.Reporter) (*Client, error) {
	var publisher *hydro.Publisher
	var err error

	// if not production, set sink as local
	if len(config.KafkaBrokers) > 0 {
		publisher, err = buildProductionHydroPublisher(config, logger)
	} else {
		publisher, err = buildDevelopmentHydroPublisher()
	}

	if err != nil {
		return &Client{
			publisher: nil,
		}, err
	}

	// Create a buffered channel
	msgChan := make(chan any, 100) // Buffer size of 100

	client := &Client{
		publisher: publisher,
		msgChan:   msgChan,
		logger:    logger,
		reporter:  reporter,
	}

	// Start a goroutine to send messages from the channel
	go client.sendMessages()

	return client, nil
}

// sendMessages sends messages from the msgChan channel
func (h *Client) sendMessages() {
	for msg := range h.msgChan {
		switch m := msg.(type) {
		case *CreateAttestationHydroMessage:
			h.helperSendCreateAttestationHydroMessage(m)
		case *GetAttestationHydroMessage:
			h.helperSendGetAttestationHydroMessage(m)
		default:
			h.logger.Warn("unknown message type")
		}
	}
}

func (h *Client) ReportError(fields map[string]string, err error) {
	if h.reporter == nil {
		return
	}
	_ = h.reporter.Report(context.Background(), err, fields)
}

func (h *Client) LogError(fields map[string]string, err error) {
	if h.logger == nil {
		return
	}
	// cast fields to zapcore.Field
	pairs := make([]kvp.Field, 0, len(fields))
	for k, v := range fields {
		pairs = append(pairs, kvp.String(k, v))
	}
	h.logger.Error(err.Error(), pairs...)
}

// Helper send CreateAttestationHydroMessage to the client
func (h *Client) helperSendCreateAttestationHydroMessage(msg *CreateAttestationHydroMessage) {
	// get the workflowRunID
	b, err := sgbundle.NewBundle(msg.bundle)
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	workflowRunID, err := attestation.GetWorkflowRunIDFromBundle(b)
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	envelope, err := b.Envelope()
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	statement, err := envelope.Statement()
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	// TODO: handle multiple subjects
	subjects, err := attestation.ValidateStatement(statement)
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	data, err := b.MarshalJSON()
	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}

	message := hydro_pb.CreateAttestation{
		// cast uint64 to int64
		OwnerId:         safeCastUint64ToInt64(msg.ownerID),
		RepositoryId:    safeCastUint64ToInt64(msg.repoID),
		TenantId:        safeCastUint64ToInt64(msg.tenantID),
		WorkflowRunId:   safeCastUint64ToInt64(workflowRunID),
		SubjectName:     subjects[0].Name,
		SubjectDigest:   subjects[0].SubjectDigest.String(),
		AttestationType: statement.Type,
		PredicateType:   statement.PredicateType,
		AttestationSize: int64(len(data)),
		SubjectsCount:   int64(len(subjects)),
	}

	err = h.publisher.Publish(&message)

	if err != nil {
		h.ReportError(msg.fields, err)
		h.LogError(msg.fields, err)
		return
	}
}

func (h *Client) helperSendGetAttestationHydroMessage(m *GetAttestationHydroMessage) {
	var hm = hydro_pb.GetAttestation{
		TenantId:          safeCastUint64ToInt64(m.TenantID),
		OwnerId:           safeCastUint64ToInt64(m.OwnerID),
		RepositoryId:      safeCastUint64ToInt64(m.RepositoryID),
		ActorId:           safeCastUint64ToInt64(m.ActorID),
		InstallationId:    safeCastUint64ToInt64(m.InstallationID),
		SsiiTargetId:      safeCastUint64ToInt64(m.SSIITargetID),
		SsiiRepositoryId:  safeCastUint64ToInt64(m.SSIIRepositoryID),
		PredicateType:     m.PredicateType,
		CreatedAt:         timestamppb.New(m.CreatedAt),
		RunnerEnvironment: m.RunnerEnvironment,
		RepoVisibility:    m.RepoVisibility,
		GitRef:            m.GitRef,
		SubjectsCount:     int64(m.SubjectsCount),
	}

	if err := h.publisher.Publish(&hm); err != nil {
		h.ReportError(m.fields, err)
		h.LogError(m.fields, err)
	}
}

// SendCreateAttestationHydroMessage is to publish CreateAttestation
// inserting the message into the buffered channel.
func (h *Client) SendCreateAttestationHydroMessage(ctx context.Context, bundle *v1.Bundle, ownerID uint64, repoID uint64, tenantID uint64) {
	if h == nil || h.publisher == nil {
		return
	}

	// store the context fields to avoid context gone before sending hydro message
	fields := map[string]string{}

	fields[o11y.GitHubRequestIDLabel] = requestid.GetGitHubRequestID(ctx)

	if npmReqID, ok := ctx.Value(o11y.NpmCtxKeyName).(string); ok {
		fields[o11y.NpmRequestIDLabel] = npmReqID
	}

	message := CreateAttestationHydroMessage{
		bundle:   bundle,
		ownerID:  ownerID,
		repoID:   repoID,
		tenantID: tenantID,
		fields:   fields,
	}

	// Send the message to the channel instead of directly publishing it
	h.msgChan <- &message
}

// SendGetAttestationMessage puts a message on the in-memory queue for
// later publishing to hydro.
func (h *Client) SendGetAttestationHydroMessage(ctx context.Context, m *GetAttestationHydroMessage) {
	if h == nil || h.publisher == nil {
		return
	}

	m.fields = map[string]string{
		o11y.GitHubRequestIDLabel: requestid.GetGitHubRequestID(ctx),
	}

	h.msgChan <- m
}

// Close closes the Publisher by flushing and closing its Sink.
func (h *Client) Close() error {
	// Close the message channel to signal the sendMessages goroutine to exit
	close(h.msgChan)
	return h.publisher.Close()
}

// Builds the publisher and overrides the default protobuf encoder with a JSON encoder to produce
// human-readable output rather than protobuf bytes.
func buildDevelopmentHydroPublisher() (*hydro.Publisher, error) {
	var logger = basicLogger.New(os.Stdout, "", basicLogger.Ldate|basicLogger.Ltime|basicLogger.Lshortfile)
	sink := hydro.NewLogSink(logger)

	return hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewJSONEncoder()))
}

// Builds the publisher and sets the production sink config
func buildProductionHydroPublisher(config Config, logger log.Logger) (*hydro.Publisher, error) {
	// Set the kafka logger to surface any problems from sarama, the underlying kafka client library.
	hydroLogger := LoggerAdapterForHydro{
		Logger: logger,
	}

	hydro.SetKafkaLogger(&hydroLogger)

	// Point the production KafkaSink at the potomac kafka brokers.
	// Use port 9093 for SSL (required).
	kc, err := hydro.NewKafkaConfig(config.KafkaBrokers,
		// TODO: set this as runtime config
		// The client ID uniquely identifies your app in logs and metrics. <app>-<environment> is a good choice.
		hydro.WithClientID(config.KafkaClientID),
		// TODO: set this as runtime config
		// Add the root CA for SSL. This cert is available on all hosts and kube containers.
		hydro.WithRootCA(config.KafkaRootCA))
	if err != nil {
		return nil, err
	}

	// A sink is responsible for writing events to a destination.
	sink, err := hydro.NewKafkaSink(*kc)
	if err != nil {
		return nil, err
	}

	return hydro.NewPublisher(sink)
}

func safeCastUint64ToInt64(value uint64) int64 {
	if value > math.MaxInt64 {
		return math.MaxInt64
	}
	// #nosec G115: Ignore overflow warning for casting uint64 to int64
	return int64(value)
}
