# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ResultTokenTest < GitHub::TestCase
    include GitHub::CommandPaletteTestHelpers

    test "creates token hash with value" do
      token = CommandPalette::ResultToken.new(text: "/github", type: "repository", id: "123", value: "github")
      assert_token_structure(token)
      assert_equal token.text, "/github"
      assert_equal token.type, "repository"
      assert_equal token.id, "123"
      assert_equal token.value, "github"
    end

    test "creates token hash and default value" do
      token = CommandPalette::ResultToken.new(text: "github", type: "owner", id: "123")
      assert_token_structure(token)
      assert_equal token.text, "github"
      assert_equal token.type, "owner"
      assert_equal token.id, "123"
      assert_equal token.value, "github"
    end

    def assert_token_structure(token)
      assert token.respond_to?(:as_json), "doesn't respond to #as_json"
      assert token.as_json.is_a?(Hash), "#as_json doesn't return Hash"

      parsed_token = JSON.parse(token.to_json).deep_symbolize_keys

      assert_expected_type("[text]", parsed_token[:text], String)
      assert_expected_type("[type]", parsed_token[:type], String)
      assert_expected_type("[id]", parsed_token[:id], String)
      assert_expected_type("[value]", parsed_token[:value], String)
    end
  end
end
