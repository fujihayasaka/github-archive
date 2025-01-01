# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsageMetricTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#actual_language_name" do
    test "uses LanguageName name if language_name_id is provided" do
      lang = create(:language_name, name: "ruby")
      usage_metric = create(:copilot_usage_metric, language_name_id: lang.id)
      assert_equal lang.name, usage_metric.actual_language_name
    end

    test "uses LanguageName name if language_name_id is provided even if language is also provided somehow" do
      lang = create(:language_name, name: "ruby")
      usage_metric = create(:copilot_usage_metric, language_name_id: lang.id, language: "nix")
      assert_equal lang.name, usage_metric.actual_language_name
    end

    test "uses language column value if language_name_id is not provided" do
      usage_metric = create(:copilot_usage_metric, language_name_id: 0, language: "javascript")
      assert_equal "javascript", usage_metric.actual_language_name
    end

    test "uses language column value if language_name_id is nil" do
      usage_metric = create(:copilot_usage_metric, language_name_id: nil, language: "javascript")
      assert_equal "javascript", usage_metric.actual_language_name
    end
  end
end
