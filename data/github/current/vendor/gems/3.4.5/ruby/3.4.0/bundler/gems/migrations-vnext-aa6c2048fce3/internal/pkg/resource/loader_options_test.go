package resource

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/stretchr/testify/assert"
)

func Test_ResourceLoaderWithImporterClient(t *testing.T) {
	r := &LoaderImpl{}
	importer := &client.DummyImporter{}
	WithImportClient(importer)(r)

	assert.Same(t, importer, r.importClient)
}

func Test_ResourceLoaderWithLogger(t *testing.T) {
	r := &LoaderImpl{}
	logger := log.NewNullLogger()
	WithLogger(logger)(r)

	assert.Same(t, logger, r.logger)
}

func Test_ResourceLoaderWithStatter(t *testing.T) {
	r := &LoaderImpl{}
	statter := stats.NullStatter
	WithStatter(statter)(r)

	assert.Same(t, statter, r.statter)
}
