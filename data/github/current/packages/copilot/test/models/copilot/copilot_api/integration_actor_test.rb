# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotCopilotApiIntegrationActorTest < GitHub::TestCase
  test "can be enabled for an integration" do
    feature_name = "test-feature"

    # Explicitly disable the flag for everyone
    disable_feature_flag(feature_name)

    actor = Copilot::CopilotApi::IntegrationActor.new("integration-id")
    refute actor.feature_enabled?(feature_name.to_sym)
    enable_feature_flag(feature_name, actor)

    # Need to reload the actor to bust memoization
    actor = Copilot::CopilotApi::IntegrationActor.new("integration-id")
    assert actor.feature_enabled?(feature_name.to_sym)
  end
end
