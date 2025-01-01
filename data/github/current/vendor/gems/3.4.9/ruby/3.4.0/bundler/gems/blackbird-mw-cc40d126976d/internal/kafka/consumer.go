package kafka

import (
	"context"

	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/blackbird-mw/internal/db"
)

//go:generate counterfeiter . IngestConsumer
type IngestConsumer interface {
	ReadMessage(context.Context) (hydro.Message, *db.CorpusState, error)
	MarkMessage(hydro.Message) error
}
