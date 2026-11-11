package agenticapp

import (
	"errors"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
)

// IsAgenticFunc is a function that checks if an actor is associated with an Agentic App.
type IsAgenticFunc func(sweagentd.ActorLogin) (sweagentd.AgenticApp, bool)

// Provider manages different Agentic Apps.
type Provider struct {
	// copilotApp is not included in the apps slice since it is special
	// to the system.
	copilotApp *Copilot

	apps []sweagentd.AgenticApp

	// allApps is a cached slice of all agentic apps including copilotApp, so that
	// we don't have to reconstruct it every time.
	allApps []sweagentd.AgenticApp
}

// ErrAgentNotFound is returned when an agent with the specified ID is not found.
var ErrAgentNotFound = errors.New("agent not found")

// NewProvider creates a new Provider instance.
func NewProvider(copilotApp *Copilot, apps ...sweagentd.AgenticApp) *Provider {
	return &Provider{
		copilotApp: copilotApp,
		apps:       apps,
		allApps:    append([]sweagentd.AgenticApp{copilotApp}, apps...),
	}
}

// CopilotApp returns the Copilot app instance managed by this provider.
func (p *Provider) CopilotApp() *Copilot {
	return p.copilotApp
}

// IsCopilotApp returns true if the provided app ID corresponds to the Copilot app.
func (p *Provider) IsCopilotApp(appID int64) bool {
	return appID == 0 || // Defaults to Copilot's Agentic app
		appID == 946600 || // Copilot Code Review App ID
		appID == p.copilotApp.AppID()
}

// ActorLogin represents a GitHub actor's login name.
type ActorLogin struct {
	login string
}

// GetLogin returns the login string for the actor.
func (a ActorLogin) GetLogin() string {
	return a.login
}

// ActorLoginFromString creates an ActorLogin from a login string.
func ActorLoginFromString(login string) ActorLogin {
	return ActorLogin{login}
}

// ActorLoginsFromStrings creates a slice of ActorLogin from a slice of login strings.
func ActorLoginsFromStrings(logins []string) []sweagentd.ActorLogin {
	var actors []sweagentd.ActorLogin
	for _, login := range logins {
		actors = append(actors, ActorLoginFromString(login))
	}

	return actors
}

// IsAgenticActor checks if the given actor is associated with any Agentic App.
func (p *Provider) IsAgenticActor(actor sweagentd.ActorLogin) (sweagentd.AgenticApp, bool) {
	if p.copilotApp.hasLogin(actor.GetLogin()) {
		return p.copilotApp, true
	}

	for _, app := range p.apps {
		if agenticApp, ok := app.(interface {
			hasLogin(string) bool
		}); ok {
			if agenticApp.hasLogin(actor.GetLogin()) {
				return app, true
			}
		}
	}

	return nil, false
}

// HasAnyAgenticActor checks if any actor in the provided list is associated with an Agentic App.
func (p *Provider) HasAnyAgenticActor(actors []sweagentd.ActorLogin) (sweagentd.AgenticApp, bool) {
	for _, actor := range actors {
		if app, ok := p.IsAgenticActor(actor); ok {
			return app, true
		}
	}

	return nil, false
}

// IsAgenticMention checks if the given body text contains a mention of any Agentic App.
func (p *Provider) IsAgenticMention(body string) (sweagentd.AgenticApp, bool) {
	if p.copilotApp.isMentioned(body) {
		return p.copilotApp, true
	}

	for _, app := range p.apps {
		if agenticApp, ok := app.(interface {
			isMentioned(string) bool
		}); ok {
			if agenticApp.isMentioned(body) {
				return app, true
			}
		}
	}

	return nil, false
}

// MentionResult contains the result of parsing a mention from a body text.
type MentionResult struct {
	App   sweagentd.AgenticApp
	Model string
}

// IsAgenticMentionWithModel checks if the given body text contains a mention of any Agentic App,
// and extracts any model selection from the mention (e.g., "@copilot+claude-opus.4.5").
// Returns the app and model if found.
func (p *Provider) IsAgenticMentionWithModel(body string) (*MentionResult, bool) {
	// First, check if there's a @copilot+model mention
	if model, ok := p.copilotApp.isMentionedWithModel(body); ok {
		return &MentionResult{
			App:   p.copilotApp,
			Model: model,
		}, true
	}

	// Fall back to regular mention without model
	if p.copilotApp.isMentioned(body) {
		return &MentionResult{
			App:   p.copilotApp,
			Model: "",
		}, true
	}

	// Check other apps (they don't support model selection yet)
	for _, app := range p.apps {
		if agenticApp, ok := app.(interface {
			isMentioned(string) bool
		}); ok {
			if agenticApp.isMentioned(body) {
				return &MentionResult{
					App:   app,
					Model: "",
				}, true
			}
		}
	}

	return nil, false
}

// FindByID returns the agentic app to use based on the provided appID.
// If the provided appID is 0, it defaults to the Copilot agentic app.
// Returns ErrAgentNotFound if the provided appID doesn't match any known agents.
func (p *Provider) FindByID(appID int64) (sweagentd.AgenticApp, error) {
	// TODO: (kinseydurhamgrace) 946600 is the application ID for CCR. We can concretely decide how we want to handle this moving forward.
	if p.IsCopilotApp(appID) {
		return p.copilotApp, nil
	}

	for _, app := range p.apps {
		if appID == app.AppID() {
			return app, nil
		}
	}

	return nil, goerrors.Errorf("%w: application ID %d is not recognized. Please ensure you are using a valid GitHub Copilot token", ErrAgentNotFound, appID)
}

// FindByBotID finds an agentic app by bot ID.
func (p *Provider) FindByBotID(botID int64) (sweagentd.AgenticApp, error) {
	if botID == p.copilotApp.BotID() {
		return p.copilotApp, nil
	}

	for _, app := range p.apps {
		if botID == app.BotID() {
			return app, nil
		}
	}

	return nil, ErrAgentNotFound
}

// Apps returns all managed agentic apps including the Copilot app.
func (p *Provider) Apps() []sweagentd.AgenticApp {
	return p.allApps
}
