package agenticapp

import (
	"testing"

	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

func TestThirdParty_NewThirdParty(t *testing.T) {
	appLogin := "my-agent"
	botID := int64(2)
	botLogin := "my-agent[bot]"
	commitLogin := "commit-login"
	commitEmail := "commit@email.com"

	tp := NewThirdParty(1, appLogin, "", botID, botLogin, commitLogin, commitEmail, nil, nil)
	require.NotNil(t, tp)
	require.Equal(t, int64(1), tp.AppID())
	require.Equal(t, appLogin, tp.AppName())
	require.Equal(t, botID, tp.BotID())
	require.Equal(t, botLogin, tp.BotLogin())
	require.Equal(t, commitLogin, tp.CommitLogin())
	require.Equal(t, commitEmail, tp.CommitEmail())
	require.Equal(t, "my-agent[agent]", tp.MentionableSlug())
}

func TestThirdParty_MentionableSlug_UsesSlugWhenProvided(t *testing.T) {
	tp := NewThirdParty(1, "My App With Spaces", "my-app-with-spaces", 2, "bot", "commit", "email", nil, nil)
	require.Equal(t, "my-app-with-spaces[agent]", tp.MentionableSlug())
}

func TestThirdParty_MentionableSlug_FallsBackToAppLogin(t *testing.T) {
	tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", nil, nil)
	require.Equal(t, "my-agent[agent]", tp.MentionableSlug())
}

func TestThirdParty_hasLogin(t *testing.T) {
	tp := NewThirdParty(1, "my-agent", "", 2, "my-agent[bot]", "commit", "email", nil, nil)

	tests := []struct {
		name     string
		login    string
		expected bool
	}{
		{name: "app login", login: "my-agent", expected: true},
		{name: "app login with bot suffix", login: "my-agent[bot]", expected: true},
		{name: "bot login", login: "my-agent[bot]", expected: true},
		{name: "unknown login", login: "other-agent", expected: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, tp.hasLogin(tt.login))
		})
	}
}

func TestThirdParty_isMentioned(t *testing.T) {
	tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", nil, nil)

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{name: "mention at beginning", body: "@my-agent[agent] please help", expected: true},
		{name: "mention in middle", body: "hey @my-agent[agent] please help", expected: true},
		{name: "mention at end", body: "please help @my-agent[agent]", expected: true},
		{name: "case insensitive", body: "@MY-AGENT[agent] please help", expected: true},
		{name: "no mention", body: "just some text", expected: false},
		{name: "partial mention", body: "@my-agent help", expected: false},
		{name: "mention in backticks ignored", body: "`@my-agent[agent]` please help", expected: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, tp.isMentioned(tt.body))
		})
	}
}

func TestThirdParty_isMentioned_WithSlug(t *testing.T) {
	tp := NewThirdParty(1, "My App With Spaces", "my-app-with-spaces", 2, "bot", "commit", "email", nil, nil)

	tests := []struct {
		name     string
		body     string
		expected bool
	}{
		{name: "mention using slug", body: "@my-app-with-spaces[agent] please help", expected: true},
		{name: "mention using display name does not match", body: "@My App With Spaces[agent] please help", expected: false},
		{name: "case insensitive slug mention", body: "@MY-APP-WITH-SPACES[agent] fix this", expected: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.expected, tp.isMentioned(tt.body))
		})
	}
}

func TestThirdParty_HasSource(t *testing.T) {
	t.Run("with source", func(t *testing.T) {
		tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", &sweagentd.AgentSource{URL: "https://github.com/org/repo"}, nil)
		require.True(t, tp.HasSource())
		require.Equal(t, "https://github.com/org/repo", tp.SourceURL())
	})

	t.Run("without source", func(t *testing.T) {
		tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", nil, nil)
		require.False(t, tp.HasSource())
		require.Empty(t, tp.SourceURL())
	})
}

func TestThirdParty_Classification(t *testing.T) {
	tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", nil, nil)
	require.False(t, tp.IsGlobalApp())
	require.False(t, tp.IsPartnerApp())
	require.True(t, tp.IsThirdPartyApp())
	require.False(t, tp.IsQuotaExempt())
}

func TestThirdParty_Metadata(t *testing.T) {
	tp := NewThirdParty(1, "my-agent", "", 2, "bot", "commit", "email", nil, nil)
	require.Equal(t, map[string]string{
		sweagentd.MetadataCAPIIntegrationID: ThirdPartyAgenticCAPIIntegrationID,
	}, tp.Metadata())
	require.Equal(t, "third-party-agentic", ThirdPartyAgenticCAPIIntegrationID)
}
