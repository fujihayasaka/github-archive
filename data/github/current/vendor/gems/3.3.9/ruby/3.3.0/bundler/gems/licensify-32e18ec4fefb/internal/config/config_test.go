package config

import "testing"

func TestEnvironmentPredicates(t *testing.T) {
	t.Run("IsProduction", func(t *testing.T) {
		t.Run("returns true when HeavenEnv is set", func(t *testing.T) {
			cfg := Config{HeavenEnv: "production"}
			got := cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}

			cfg = Config{HeavenEnv: "anything"}
			got = cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})

		t.Run("returns false when HeavenEnv is not set", func(t *testing.T) {
			cfg := Config{HeavenEnv: ""}
			got := cfg.IsProduction()
			if got {
				t.Errorf("expected false, got %v", got)
			}
		})
	})
}
