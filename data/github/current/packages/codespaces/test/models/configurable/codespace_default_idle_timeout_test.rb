# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespaceDefaultIdleTimeoutTest < GitHub::TestCase
  context "hydro instrumentation" do
    test "does not instrument when feature is disabled (new setting)" do
      disable_feature_flag(:codespaces_hydro_idle_timeout)
      actor = create(:user)
      GlobalInstrumenter.expects(:instrument).at_least(0) # Otherwise test fails if anything else gets instrumented
      GlobalInstrumenter.expects(:instrument).with("codespaces.default_idle_timeout_updated", anything).never
      actor.update_codespace_default_idle_timeout(30, actor: create(:user)) # Initial setting, from default
      actor.update_codespace_default_idle_timeout(120, actor:) # Updated setting
    end

    test "instruments when feature is enabled" do
      enable_feature_flag(:codespaces_hydro_idle_timeout)
      actor = create(:user)
      GlobalInstrumenter.expects(:instrument).with("codespaces.default_idle_timeout_updated", { actor:, value_minutes: 30, previous_value_minutes: nil }).once
      actor.update_codespace_default_idle_timeout(30, actor:) # Initial setting, from default
      GlobalInstrumenter.expects(:instrument).with("codespaces.default_idle_timeout_updated", { actor:, value_minutes: 120, previous_value_minutes: 30 }).once
      actor.update_codespace_default_idle_timeout(120, actor:) # Updated setting
    end
  end
end
