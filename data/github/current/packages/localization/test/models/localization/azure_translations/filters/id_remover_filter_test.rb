# typed: true
# frozen_string_literal: true

require_relative "../../../../fast_test_helper"

class Localization::AzureTranslations::Filters::IdRemoverFitlerTest < GitHub::TestCase
  def filter(text)
    Localization::AzureTranslations::Filters::IdRemoverFilter.to_html(text)
  end

  test "it ignores any text that is not really html" do
    input = 'This is a random text with no id="something" attributes'
    expected = input

    assert_equal expected, filter(input)
  end

  test "it replaces all ids" do
    input = <<~HTML
      <div id="the-div">
        <span id="name">Name</span><span id="last-name">Last Name</span>
        <p id="welcome">Welcome</p>
      </div>
    HTML

    expected = <<~HTML
      <div>
        <span>Name</span><span>Last Name</span>
        <p>Welcome</p>
      </div>
    HTML

    assert_equal expected.gsub(/[\n\t\s]+/, ""), filter(input).gsub(/[\n\t\s]+/, "")
  end
end
