package agenticapp

import (
	"slices"

	"github.com/github/sweagentd/internal/sweagentd"
)

// Provider manages different Agentic Apps.
type Provider struct {
	copilotApp *Copilot
}

// NewProvider creates a new Provider instance.
func NewProvider(copilotApp *Copilot) *Provider {
	return &Provider{
		copilotApp: copilotApp,
	}
}

// IsAgenticActor checks if the given actor is associated with any Agentic App.
func (p *Provider) IsAgenticActor(actor sweagentd.ActorWithLogin) bool {
	return p.copilotApp.hasLogin(actor.GetLogin())
}

// HasAnyAgenticActor checks if any actor in the provided list is associated with an Agentic App.
func (p *Provider) HasAnyAgenticActor(actors []sweagentd.ActorWithLogin) bool {
	return slices.ContainsFunc(actors, p.IsAgenticActor)
}

// IsAgenticMention checks if the given body text contains a mention of any Agentic App.
func (p *Provider) IsAgenticMention(body string) bool {
	return p.copilotApp.isMentioned(body)
}
