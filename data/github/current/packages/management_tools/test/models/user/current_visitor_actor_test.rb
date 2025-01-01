# typed: true
# frozen_string_literal: true
require "test_helper"

class CurrentVisitorActorTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @enabled_id = "GH1.1.1955030087.1562868941"
    @actor = User::CurrentVisitorActor.from_current_visitor(@enabled_id)
    @feature_name = "testfeature"
    @feature = create(:flipper_feature, name: @feature_name, description: "testing device id actors")
  end

  context "#from_current_visitor" do
    test "creates actor using current visitory id" do
      refute_nil @actor
      assert_equal @actor.flipper_id, "User::CurrentVisitorActor:#{@enabled_id}"
    end
  end

  test "enables feature for device id" do
    GitHub.flipper[@feature_name].enable(@actor)
    assert GitHub.flipper[@feature_name].enabled?(@actor)
  end
end
