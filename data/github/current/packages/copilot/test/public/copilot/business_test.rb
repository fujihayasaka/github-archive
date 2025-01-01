# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessTest < GitHub::TestCase
  test "wraps a ::Business" do
    business = create(:business)
    Copilot::Business.new(business)
  end
end if GitHub.copilot_enabled?
