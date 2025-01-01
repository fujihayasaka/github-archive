# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationUrlTest < GitHub::TestCase
  test "is invalid when URL is nil" do
    url = IntegrationUrl.new(nil)

    refute_predicate url, :valid?
  end
end
