// Package views implements templating for email layouts.
package views

import (
	"bytes"
	"context"
	"embed"
	html "html/template"
	"io"
	text "text/template"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

var htmlLayouts = map[string]string{
	"base": "templates/base_layout.html.tmpl",
	// primer uses the Primer email layout
	"primer": "templates/primer_layout.html.tmpl",
	// simple mimics the original Newsies layout, using Primer attributes
	"simple": "templates/simple_layout.html.tmpl",
}

var textLayouts = map[string]string{
	"base": "templates/base_layout.txt.tmpl",
}

//go:embed templates/*
var embeddedTemplatesFS embed.FS

const (
	htmlPartials = "templates/partials/*.html.tmpl"
	textPartials = "templates/partials/*.txt.tmpl"
)

type engine interface {
	ExecuteTemplate(writer io.Writer, name string, data any) error
}

// View represents a view for an email.
type View interface {
	// TODO: Use bytes or io.Reader?
	Render(ctx context.Context, logger log.Logger, layoutName string) (string, error)
}

// TextEmailView represents a view for a text email.
type TextEmailView struct {
	Subject        string
	Body           string
	URL            string
	UnsubscribeURL string
	Reason         string
	MessageID      string
	CanReply       bool
}

// Render renders the text email view with the given layout.
func (view *TextEmailView) Render(ctx context.Context, logger log.Logger, layoutName string) (string, error) {
	tmpl, err := text.ParseFS(embeddedTemplatesFS, textPartials, textLayouts[layoutName])

	if err != nil {
		if layoutName == "base" {
			return "", err
		}

		logger.WithFields(kvp.String("gh.notifyd.layout", layoutName)).
			WithContext(ctx).WithError(err).
			Info("error rendering layout, falling back to base")
		return view.Render(ctx, logger, "base")
	}

	return renderTemplate(layoutName, tmpl, view)
}

// HTMLEmailView represents a view for an HTML email.
type HTMLEmailView struct {
	Subject        string
	Body           html.HTML
	URL            string
	UnsubscribeURL string
	Reason         string
	CanReply       bool
}

// Render template with specific layout
func (view *HTMLEmailView) Render(ctx context.Context, logger log.Logger, layoutName string) (string, error) {
	tmpl, err := html.ParseFS(embeddedTemplatesFS, htmlPartials, htmlLayouts[layoutName])

	if err != nil {
		if layoutName == "base" {
			return "", err
		}

		logger.WithContext(ctx).WithError(err).Info(
			"error rendering layout, falling back to base",
			kvp.String("gh.notifyd.layout", layoutName),
		)
		return view.Render(ctx, logger, "base")
	}

	return renderTemplate(layoutName, tmpl, view)
}

func renderTemplate(name string, eng engine, bindings any) (string, error) {
	buf := new(bytes.Buffer)

	err := eng.ExecuteTemplate(buf, name, bindings)
	if err != nil {
		return "", err
	}

	return buf.String(), nil
}
