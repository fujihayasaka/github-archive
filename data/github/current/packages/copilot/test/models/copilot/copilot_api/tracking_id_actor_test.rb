# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotCopilotApiTrackingIdActorTest < GitHub::TestCase
  test "can be enabled for a tracking ID" do
    feature = FlipperFeature.create(name: "test-feature", description: "test feature")

    # Explicitly disable the flag for everyone
    feature.disable

    actor = Copilot::CopilotApi::TrackingIdActor.new("123abc")
    refute actor.feature_enabled?(feature.name.to_sym)
    actor.enable_feature(feature.name)

    # Need to reload the actor to bust memoization
    actor = Copilot::CopilotApi::TrackingIdActor.new("123abc")
    assert actor.feature_enabled?(feature.name.to_sym)
  end
end
