# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class LocalizationTestMockConfig < GitHub::TestCase
  def setup
    @config = Localization::Test::MockConfig.new
  end

  test "has a primary_browser_language" do
    @config.with_primary_browser_language("pt-BR")

    assert_equal "pt", @config.primary_browser_language_without_region
  end

  test "has a primary_browser_language_name" do
    @config.with_primary_browser_language("pt-BR")

    assert_equal "Portuguese", @config.primary_browser_language_name
  end

  test "has ugct supported language" do
    @config.with_ugct_languages(%w[en pt])
    assert @config.ugct_supports_language?("en")
    assert @config.ugct_supports_language?("pt")
    refute @config.ugct_supports_language?("cn")
  end
end
