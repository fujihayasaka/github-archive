# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Policies::ConfigTest < GitHub::TestCase

  context ".display_name_for" do
    test "returns expected display name" do
      assert_equal "Anthropic Claude 3.5 Sonnet in Copilot setting", Copilot::Policies::Config.display_name_for(:a_chat)
    end

    test "returns expected display name for Desktop" do
      assert_equal "Copilot in GitHub Desktop setting", Copilot::Policies::Config.display_name_for(:desktop)
    end
  end
end
