# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/FeatureManagement/NoFlipperUsageInTests
# rubocop:disable GitHub/FeatureManagement/NoActorFeatureManipulationInTests

require "test_helper"

class FlipperSessionTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @session = FlipperSession.new(1)
  end

  setup do
    GitHub.flipper[:test_feature].disable
  end

  test "it generates unique IDs" do
    id_1 = FlipperSession.generate_id
    id_2 = FlipperSession.generate_id
    refute_equal id_1, id_2, "Expected unique IDs"
  end

  test "it does not enable features by default" do
    refute GitHub.flipper[:test_feature].enabled?(@session), "Shouldn't be enabled by default"
  end

  test "it can enable features" do
    @session.enable_feature(:test_feature)
    assert GitHub.flipper[:test_feature].enabled?(@session), "Expected feature to be enabled"
  end

  test "remembers enabling features" do
    @session.enable_feature(:test_feature)
    reprised = FlipperSession.new(1)
    assert GitHub.flipper[:test_feature].enabled?(reprised), "Expected feature to be enabled"
  end

  test "it can disable features" do
    @session.enable_feature(:test_feature)
    @session.disable_feature(:test_feature)
    refute GitHub.flipper[:test_feature].enabled?(@session), "Expected feature to be disabled"
  end

  test "remembers disabling features" do
    @session.enable_feature(:test_feature)
    @session.disable_feature(:test_feature)
    reprised = FlipperSession.new(1)
    refute GitHub.flipper[:test_feature].enabled?(reprised), "Expected feature to be disabled"
  end

  test "it can discriminate between sessions" do
    @session.enable_feature(:test_feature)
    other_session = FlipperSession.new(2)
    refute GitHub.flipper[:test_feature].enabled?(other_session), "Expected feature to be disabled"
  end

  test "it defers to global feature settings" do
    GitHub.flipper[:test_feature].enable_percentage_of_actors(100)
    assert GitHub.flipper[:test_feature].enabled?(@session), "Expected feature to be enabled"
    GitHub.flipper[:test_feature].enable_percentage_of_actors(0)
  end

  test "it converts string id to integer" do
    assert_equal 1, FlipperSession.new("1").id
  end

  test "it raises exception if string id cannot be converted" do
    assert_raises ArgumentError do
      FlipperSession.new("gobbledgook")
    end
  end

  test "can compare equality" do
    assert_equal FlipperSession.new(1), FlipperSession.new(1)
    refute_equal FlipperSession.new(2), FlipperSession.new(1)
    refute_equal Object.new, FlipperSession.new(1)
  end
end
