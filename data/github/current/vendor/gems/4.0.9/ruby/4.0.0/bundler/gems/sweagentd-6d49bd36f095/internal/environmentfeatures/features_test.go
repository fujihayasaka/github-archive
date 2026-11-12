package environmentfeatures

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestDefault(t *testing.T) {
	f := Default
	assert.False(t, f.IsUnset())
	assert.NotNil(t, f.CopilotSetupSteps)
	assert.NotNil(t, f.PullRequest)
	assert.Nil(t, f.Branch)
}

func TestNew(t *testing.T) {
	f := New()
	assert.False(t, f.IsUnset())
	assert.Nil(t, f.CopilotSetupSteps)
	assert.Nil(t, f.Branch)
	assert.Nil(t, f.PullRequest)
}

func TestFeatures_IsUnset(t *testing.T) {
	t.Run("true when zero value", func(t *testing.T) {
		f := Features{}
		assert.True(t, f.IsUnset())
	})

	t.Run("true for Unset var", func(t *testing.T) {
		assert.True(t, Unset.IsUnset())
	})

	t.Run("false when explicitly created with New", func(t *testing.T) {
		f := New()
		assert.False(t, f.IsUnset())
	})

	t.Run("false when any feature is set", func(t *testing.T) {
		f := Features{CopilotSetupSteps: &CopilotSetupSteps{}}
		assert.False(t, f.IsUnset())

		f = Features{Branch: &Branch{Name: "main"}}
		assert.False(t, f.IsUnset())

		f = Features{PullRequest: &PullRequest{BaseRef: "main"}}
		assert.False(t, f.IsUnset())
	})
}

func TestFeatures_CopilotSetupStepsEnabled(t *testing.T) {
	t.Run("enabled with default features", func(t *testing.T) {
		f := Default
		assert.True(t, f.CopilotSetupStepsEnabled())
	})

	t.Run("enabled when copilot-setup-steps not configured", func(t *testing.T) {
		f := Features{}
		assert.True(t, f.CopilotSetupStepsEnabled())
	})

	t.Run("enabled when copilot-setup-steps present", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{},
		}
		assert.True(t, f.CopilotSetupStepsEnabled())
	})

	t.Run("enabled with custom setup steps present", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{},
		}
		assert.True(t, f.CopilotSetupStepsEnabled())
	})

	t.Run("disabled when Skip is true", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Skip: true,
			},
		}
		assert.False(t, f.CopilotSetupStepsEnabled())
	})
}

func TestFeatures_CopilotSetupStepsPropertyExcluded(t *testing.T) {
	t.Run("false when CopilotSetupSteps is nil", func(t *testing.T) {
		f := Features{}
		assert.False(t, f.CopilotSetupStepsPropertyExcluded("steps"))
	})

	t.Run("false when Exclude is empty", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{},
		}
		assert.False(t, f.CopilotSetupStepsPropertyExcluded("steps"))
	})

	t.Run("true when property is in Exclude list", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Exclude: []string{"steps", "permissions"},
			},
		}
		assert.True(t, f.CopilotSetupStepsPropertyExcluded("steps"))
		assert.True(t, f.CopilotSetupStepsPropertyExcluded("permissions"))
	})

	t.Run("false when property is not in Exclude list", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Exclude: []string{"steps"},
			},
		}
		assert.False(t, f.CopilotSetupStepsPropertyExcluded("runs-on"))
		assert.False(t, f.CopilotSetupStepsPropertyExcluded("permissions"))
	})
}

func TestFeatures_CopilotSetupStepsHasOnly(t *testing.T) {
	t.Run("false when CopilotSetupSteps is nil", func(t *testing.T) {
		f := Features{}
		assert.False(t, f.CopilotSetupStepsHasOnly())
	})

	t.Run("false when Only is empty", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{},
		}
		assert.False(t, f.CopilotSetupStepsHasOnly())
	})

	t.Run("true when Only is non-empty", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Only: []string{"runs-on"},
			},
		}
		assert.True(t, f.CopilotSetupStepsHasOnly())
	})
}

func TestFeatures_CopilotSetupStepsPropertyAllowed(t *testing.T) {
	t.Run("true when CopilotSetupSteps is nil", func(t *testing.T) {
		f := Features{}
		assert.True(t, f.CopilotSetupStepsPropertyAllowed("steps"))
	})

	t.Run("true when Only is empty", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{},
		}
		assert.True(t, f.CopilotSetupStepsPropertyAllowed("steps"))
		assert.True(t, f.CopilotSetupStepsPropertyAllowed("runs-on"))
	})

	t.Run("true when property is in Only list", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Only: []string{"runs-on", "container"},
			},
		}
		assert.True(t, f.CopilotSetupStepsPropertyAllowed("runs-on"))
		assert.True(t, f.CopilotSetupStepsPropertyAllowed("container"))
	})

	t.Run("false when property is not in Only list", func(t *testing.T) {
		f := Features{
			CopilotSetupSteps: &CopilotSetupSteps{
				Only: []string{"runs-on"},
			},
		}
		assert.False(t, f.CopilotSetupStepsPropertyAllowed("steps"))
		assert.False(t, f.CopilotSetupStepsPropertyAllowed("permissions"))
	})
}
