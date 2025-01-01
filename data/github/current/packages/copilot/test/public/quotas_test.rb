# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotQuotasTest < GitHub::TestCase

  include CopilotTestHelper

  context ".monthly_quotas" do
    test "defaults to defaults" do
      assert_equal 500, Copilot::Quotas.monthly_quotas["chat"]
      assert_equal 2000, Copilot::Quotas.monthly_quotas["completions"]
    end
  end
end
