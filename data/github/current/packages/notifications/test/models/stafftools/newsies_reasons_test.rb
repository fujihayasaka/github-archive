# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsiesReasonsTester
  include Stafftools::NewsiesReasons

  attr_reader :reason

  def initialize(reason)
    @reason = reason
  end
end

class StafftoolsNewsiesReasonsTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @mention = NewsiesReasonsTester.new("mention")
    @unknown_reason = NewsiesReasonsTester.new("unknown_reason")
  end

  context "#human_reason" do
    test "returns a human-friendly string" do
      assert_equal "directly mentioned", @mention.human_reason
    end

    test "returns the raw reason when no string is defined" do
      assert_equal "unknown_reason", @unknown_reason.human_reason
    end
  end
end
