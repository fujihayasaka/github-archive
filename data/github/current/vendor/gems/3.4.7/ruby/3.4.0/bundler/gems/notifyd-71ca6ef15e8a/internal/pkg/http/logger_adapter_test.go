package http

import (
	"testing"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/notifyd/internal/pkg/http/mocks"
)

func Test_Logging(t *testing.T) {
	mock := mocks.NewLoggerMock(t)

	t.Run("with even k-v", func(t *testing.T) {
		logger := &leveledLoggerAdapter{logger: mock}
		mock.EXPECT().Info("hi", kvp.Any("1", 1), kvp.Any("2", 2))

		logger.Info("hi", "1", 1, "2", 2)
	})

	t.Run("with odd k-v", func(t *testing.T) {
		logger := &leveledLoggerAdapter{logger: mock}
		mock.EXPECT().Info("hi", kvp.Any("1", 1), kvp.Any("2", ""))

		logger.Info("hi", "1", 1, "2")
	})
}
