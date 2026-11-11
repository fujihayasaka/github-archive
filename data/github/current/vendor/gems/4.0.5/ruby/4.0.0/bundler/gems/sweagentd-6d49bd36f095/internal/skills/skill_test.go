package skills

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSkill(t *testing.T) {
	t.Run("getters return metadata values", func(t *testing.T) {
		skill := NewSkill(Metadata{
			Name:        "test-skill",
			RepoID:      123,
			RepoOwner:   "owner",
			RepoOwnerID: 456,
			RepoName:    "repo",
			Version:     "abc123def",
		}, "Test description", "content", []string{"Read"}, false, true)

		assert.Equal(t, "test-skill", skill.Name())
		assert.Equal(t, int64(123), skill.RepoID())
		assert.Equal(t, "owner", skill.RepoOwner())
		assert.Equal(t, int64(456), skill.RepoOwnerID())
		assert.Equal(t, "repo", skill.RepoName())
		assert.Equal(t, "abc123def", skill.Version())
	})

	t.Run("getters return config values", func(t *testing.T) {
		skill := NewSkill(Metadata{
			Name: "config-skill",
		}, "My description", "My content", []string{"Read", "Write"}, true, false)

		assert.Equal(t, "My description", skill.Description())
		assert.Equal(t, "My content", skill.Content())
		assert.Equal(t, []string{"Read", "Write"}, skill.AllowedTools())
		assert.True(t, skill.DisableModelInvocation())
		assert.False(t, skill.UserInvocable())
	})

	t.Run("nil config returns defaults", func(t *testing.T) {
		skill := &Skill{
			metadata: Metadata{Name: "bare-skill"},
			config:   nil,
		}

		assert.Equal(t, "bare-skill", skill.Name())
		assert.Equal(t, "", skill.Description())
		assert.Equal(t, "", skill.Content())
		assert.Nil(t, skill.AllowedTools())
		assert.True(t, skill.UserInvocable())           // Default true
		assert.False(t, skill.DisableModelInvocation()) // Default false
	})

	t.Run("empty allowed tools", func(t *testing.T) {
		skill := NewSkill(Metadata{Name: "no-tools"}, "desc", "content", nil, false, true)

		assert.Nil(t, skill.AllowedTools())
	})

	t.Run("empty allowed tools slice", func(t *testing.T) {
		skill := NewSkill(Metadata{Name: "empty-tools"}, "desc", "content", []string{}, false, true)

		assert.Equal(t, []string{}, skill.AllowedTools())
	})
}
