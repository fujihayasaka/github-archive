# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotCopilotApiIntegrationActorTest < GitHub::TestCase
  test "can be enabled for an integration" do
    feature = FlipperFeature.create(name: "test-feature", description: "test feature")

    # Explicitly disable the flag for everyone
    feature.disable

    actor = Copilot::CopilotApi::IntegrationActor.new("integration-id")
    refute actor.feature_enabled?(feature.name.to_sym)
    actor.enable_feature(feature.name)

    # Need to reload the actor to bust memoization
    actor = Copilot::CopilotApi::IntegrationActor.new("integration-id")
    assert actor.feature_enabled?(feature.name.to_sym)
  end
end
