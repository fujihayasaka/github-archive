// Package integration contains integration tests that exercise the entire system
package integration

// This file contains util functions for tests

import (
	"context"
	"fmt"
	"math/rand"
	"net"
	"net/url"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Azure/azure-storage-blob-go/azblob"
	klbroker "github.com/github/kafka-lite/broker"
	"github.com/github/kafka-lite/log"
	klserver "github.com/github/kafka-lite/server"
	"github.com/github/kafka-lite/store/memory"
	"github.com/segmentio/kafka-go"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

const (
	// TestAccountName is the default account name for the azurite docker image
	TestAccountName = "devstoreaccount1"
	// TestAccountKey is the default account key for the azurite docker image
	TestAccountKey = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
)

// kafkaLiteInstance is a KafkaLite server instance.
// We can only have one instance of KafkaLite running at a time for all tests.
type kafkaLiteInstance struct {
	server *klserver.Server
	addr   string
}

var (
	mutex    sync.Mutex
	instance kafkaLiteInstance
)

// availableTCPPort returns an available tcp port
func availableTCPPort(t testing.TB) int {
	t.Helper()
	addr, err := net.ResolveTCPAddr("tcp", "localhost:0")
	require.NoError(t, err)

	l, err := net.ListenTCP("tcp", addr)
	require.NoError(t, err)
	tcp, ok := l.Addr().(*net.TCPAddr)
	require.True(t, ok)
	require.NoError(t, l.Close())
	return tcp.Port
}

// RandomString generates a random string of A-Z chars with len = l
func RandomString(length int) string {
	bytes := make([]byte, length)
	for i := range length {
		bytes[i] = byte(randomInt(65, 90))
	}
	return string(bytes)
}

// randomInt returns an int >= min, < max
func randomInt(minVal, maxVal int) int {
	//nolint:gosec // this needs to be deterministic
	return minVal + rand.Intn(maxVal-minVal)
}

// SetupKafkaLiteTest starts kafka-lite and returns its brokers
func SetupKafkaLiteTest(t *testing.T) string {
	t.Helper()

	mutex.Lock()
	defer mutex.Unlock()

	// NOTE - we create only once instance of the KafkaLite server. We don't create multiple instances because it causes flakiness.
	// We also don't stop the server after creating it because KafkaLite seems to have a data race in the shutdown code.
	if instance.server == nil {
		log.SetLogger(zap.NewNop())
		port := availableTCPPort(t)
		instance.addr = fmt.Sprintf("127.0.0.1:%d", port)
		store := memory.NewStore()
		broker, err := klbroker.NewBroker(store, klbroker.Config{
			AdvertisedAddr: instance.addr,
		})

		require.NoError(t, err)

		s := klserver.NewServer(memory.NewStore(), broker, instance.addr)
		instance.server = &s

		err = instance.server.Start()
		require.NoError(t, err)

		requireKafkaReady(t, instance.addr)
	}

	return instance.addr
}

// requireKafkaReady test helper to require that kafka is ready before proceeding
func requireKafkaReady(t *testing.T, brokers string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	topic := RandomString(10)
	msgs, err := makeKafkaMsgs(1)
	require.NoError(t, err)
	var conn *kafka.Conn
	for {
		conn, err = kafka.DialLeader(ctx, "tcp", brokers, topic, 0)
		if err == nil {
			break
		}
		select {
		case <-time.After(time.Second):
		case <-ctx.Done():
			require.FailNow(t, "timed out")
		}
	}

	for range 60 {
		_, err = conn.WriteMessages(msgs...)
		if err == nil {
			break
		}
		time.Sleep(time.Second)
	}

	require.NoError(t, err)
	require.NoError(t, conn.Close())
}

// makeKafkaMsgs returns test messages
func makeKafkaMsgs(n int) ([]kafka.Message, error) {
	msgs := make([]kafka.Message, n)
	for i := range msgs {
		msgs[i] = kafka.Message{
			Value: []byte("foo"),
		}
	}
	return msgs, nil
}

// DockerComposePort returns the result of running `docker compose port <service> <internalPort>`
func DockerComposePort(t testing.TB, service string, internalPort int) string {
	//nolint:gosec // G204: Subprocess launched with a potential tainted input or cmd arguments:qa
	cmd := exec.Command("docker", "compose", "port", service, fmt.Sprintf("%d", internalPort))
	got, err := cmd.CombinedOutput()
	require.NoErrorf(t, err, "error running docker compose port. output was: %s\n%s", got, err)
	return strings.TrimSpace(string(got))
}

// SetupAzuriteTest creates a new container in azurite and returns its URL
func SetupAzuriteTest(t *testing.T) *azblob.ContainerURL {
	t.Helper()
	ctx := context.Background()

	azuriteURL := "http://" + DockerComposePort(t, "azurite", 10000)
	containerName := strings.ToLower(RandomString(8))
	containerString := fmt.Sprintf("%s/%s/%s", azuriteURL, TestAccountName, containerName)
	creds, err := azblob.NewSharedKeyCredential(TestAccountName, TestAccountKey)
	require.NoError(t, err)

	pipe := azblob.NewPipeline(creds, azblob.PipelineOptions{})

	containerURL, err := url.Parse(containerString)
	require.NoError(t, err)

	containerService := azblob.NewContainerURL(*containerURL, pipe)
	_, err = containerService.Create(ctx, azblob.Metadata{}, azblob.PublicAccessNone)
	require.NoError(t, err)

	return &containerService
}

// GetCurrentDir returns the current directory of the test file
func GetCurrentDir(t *testing.T) string {
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatalf("Unable to get caller information")
	}
	return filepath.Dir(filename)
}
