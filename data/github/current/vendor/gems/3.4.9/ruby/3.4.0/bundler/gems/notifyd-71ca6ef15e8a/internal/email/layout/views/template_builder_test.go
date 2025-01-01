package views

import (
	"context"
	"testing"

	stats_mock "github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func TestCreateTemplate(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	statsMock := new(stats_mock.Client)
	statsMock.On("DistributionMs", "building_template.time", mock.Anything, mock.Anything)
	emailProcessorMock := pipeline.NewPostProcessorMock(t)
	emailProcessorMock.On("Process", mock.Anything, mock.Anything, mock.Anything).Return("<body>processed content</body>", nil)
	notification := datastructures.Notification{Subject: "subject", Body: "body"}
	template := NewTemplate(logs.NullTelem, statsMock, "primer", emailProcessorMock)

	newNotification, err := template.CreateTemplate(ctx, tenancy.NewSingleTenant(), &notification)
	r.Equal("<body>processed content</body>", newNotification.Body)
	r.NoError(err)
}

func TestCreateTemplateWithTextPart(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	statsMock := new(stats_mock.Client)
	statsMock.On("DistributionMs", "building_template.time", mock.Anything, mock.Anything)
	emailProcessorMock := pipeline.NewPostProcessorMock(t)
	emailProcessorMock.On("Process", mock.Anything, mock.Anything, mock.Anything).Return("<body>processed content</body>", nil)
	notification := datastructures.Notification{Subject: "subject", Body: "body", TextBody: "text body"}
	template := NewTemplate(logs.NullTelem, statsMock, "primer", emailProcessorMock)

	newNotification, err := template.CreateTemplate(ctx, tenancy.NewSingleTenant(), &notification)
	r.Equal("<body>processed content</body>", newNotification.Body)
	r.Contains(newNotification.TextBody, "text body")
	r.NoError(err)
}

func TestCreateTemplateWithoutProcessor(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	statsMock := new(stats_mock.Client)
	statsMock.On("DistributionMs", "building_template.time", mock.Anything, mock.Anything)
	notification := datastructures.Notification{Subject: "subject", Body: "test-body"}
	template := NewTemplate(logs.NullTelem, statsMock, "primer", nil)

	newNotification, err := template.CreateTemplate(ctx, tenancy.NewSingleTenant(), &notification)
	r.Contains(newNotification.Body, "test-body")
	r.NoError(err)
}

func TestCreateTemplateWithErrors(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()
	statsMock := new(stats_mock.Client)
	statsMock.On("DistributionMs", "building_template.time", mock.Anything, mock.Anything)

	processErr := errors.New("oops")
	emailProcessorMock := pipeline.NewPostProcessorMock(t)
	emailProcessorMock.On("Process", mock.Anything, mock.Anything, mock.Anything).Return("", processErr)
	notification := datastructures.Notification{Subject: "subject", Body: "body"}
	template := NewTemplate(logs.NullTelem, statsMock, "primer", emailProcessorMock)

	newNotification, err := template.CreateTemplate(ctx, tenancy.NewSingleTenant(), &notification)
	r.Equal("body", newNotification.Body)
	r.ErrorIs(err, processErr)
}
