package views

import (
	"context"
	htmltemplate "html/template"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	"github.com/hashicorp/go-multierror"

	"github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// TemplateBuilder represents a template builder.
type TemplateBuilder interface {
	CreateTemplate(ctx context.Context, tenant tenancy.Tenant, notification *datastructures.Notification) (*datastructures.Notification, error)
}

type template struct {
	telem     *telemetry.Provider
	statter   stats.Client
	layout    string
	processor pipeline.PostProcessor
}

// NewTemplate creates a new template.
func NewTemplate(telem *telemetry.Provider, statter stats.Client, layout string, processor pipeline.PostProcessor) TemplateBuilder {
	return template{
		telem:     telem,
		statter:   statter,
		layout:    layout,
		processor: processor,
	}
}

// CreateTemplate builds the html and text parts to deliver in several steps:
// - Rendering the html template with a layout
// - Processing the html with a monolith request
// - Processing the text with a monolith request
// It returns the plain text content as a fallback
func (t template) CreateTemplate(ctx context.Context, tenant tenancy.Tenant, notification *datastructures.Notification) (*datastructures.Notification, error) {
	logger := t.telem.Logger.WithContext(ctx)

	var allErr error
	if html, err := t.renderHTML(ctx, tenant, notification); err != nil {
		logger.WithFields(kvp.String("gh.notifyd.notification.url", notification.URL)).WithError(err).
			Error("error rendering html template, falling back to plain text version")
		allErr = multierror.Append(allErr, err)
	} else {
		notification.Body = html
	}

	if text, err := t.renderText(ctx, notification); err != nil {
		logger.WithFields(kvp.String("gh.notifyd.notification.url", notification.URL)).WithError(err).
			Error("error rendering text template, falling back to plain text version")
		allErr = multierror.Append(allErr, err)
	} else {
		notification.TextBody = text
	}

	return notification, allErr
}

func (t template) renderHTML(ctx context.Context, tenant tenancy.Tenant, notification *datastructures.Notification) (string, error) {
	statsTimer := stats.NewTimer(t.statter)
	canReply := false
	if notification.Header != nil {
		canReply = notification.Header.Has("Reply-To")
	}

	emailView := &HTMLEmailView{
		Subject: notification.Subject,
		//nolint:gosec // It is OK because the body is controlled by us.
		Body:           htmltemplate.HTML(notification.Body),
		URL:            notification.URL,
		UnsubscribeURL: notification.UnsubscribeURL,
		Reason:         reasonForEmail(notification.Reasons),
		CanReply:       canReply,
	}
	html, err := emailView.Render(ctx, t.telem.Logger, t.layout)
	if err != nil {
		t.statter.DistributionMs("building_template.time", stats.Tags{
			"status":       "failed",
			"content_type": "html",
			"error_type":   "buildingTemplate.rendering",
		}, time.Since(statsTimer.StartTime()))
		return "", err
	}
	if t.processor == nil {
		return html, nil
	}

	processedHTML, err := t.processor.Process(ctx, tenant, html)
	if err != nil {
		t.statter.DistributionMs("building_template.time", stats.Tags{
			"status":       "failed",
			"content_type": "html",
			"error_type":   "buildingTemplate.processing",
		}, time.Since(statsTimer.StartTime()))
		return "", errors.Wrap(err, "render: error post processing html")
	}

	return processedHTML, nil
}

func (t template) renderText(ctx context.Context, notification *datastructures.Notification) (string, error) {
	if notification.TextBody == "" {
		return "", nil
	}

	canReply := false
	messageID := ""
	if notification.Header != nil {
		canReply = notification.Header.Has("Reply-To")
		messageID = notification.Header.Get("Message-Id")
	}

	statsTimer := stats.NewTimer(t.statter)
	emailView := &TextEmailView{
		Subject:        notification.Subject,
		Body:           notification.TextBody,
		URL:            notification.URL,
		UnsubscribeURL: notification.UnsubscribeURL,
		Reason:         reasonForEmail(notification.Reasons),
		CanReply:       canReply,
		MessageID:      messageID,
	}

	text, err := emailView.Render(ctx, t.telem.Logger, t.layout)
	if err != nil {
		t.statter.DistributionMs("building_template.time", stats.Tags{
			"status":       "failed",
			"content_type": "text",
			"error_type":   "buildingTemplate.rendering",
		}, time.Since(statsTimer.StartTime()))
		return "", err
	}

	return text, nil
}

func reasonForEmail(reasons []string) string {
	if len(reasons) == 0 {
		return "you are subscribed to this thread"
	}

	return reasons[0]
}
