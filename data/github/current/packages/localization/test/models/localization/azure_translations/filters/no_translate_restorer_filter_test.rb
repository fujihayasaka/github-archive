# typed: true
# frozen_string_literal: true

require_relative "../../../../fast_test_helper"

class Localization::AzureTranslations::Filters::NoTranslateRestorerFilterTest < GitHub::TestCase
  setup do
    SecureRandom.stubs(:uuid).returns("uid1", "uid2", "uid3", "uid4")
  end

  test "it ignores any text that is not really html" do
    input = 'This is a random text with no id="something" attributes'
    expected = input

    assert_equal expected, filter(input)[:output].to_html
  end

  test "it replaces no-translate with placeholders and keeps track of replaced contents" do
    assert_restoration_of(
      <<~HTML
        <div id="the-div">
          <p class="foo notranslate"><span>DONT ONE</span></p>
          <p>Hi there</p> <p class="notranslate">DONT TWO</p>
          <p>Hi there again</p>
          <p class="notranslate">DONT THREE <span class="notranslate">DONT FOUR</span></p>
        </div>
      HTML
    )

    assert_restoration_of('<p class="foo notranslate"><span>Some text</span></p>')
    assert_restoration_of('<p class="foo notranslate">Some text</p>')
    assert_restoration_of('<p class="foo notranslate"></p>')
  end

  private

  def assert_restoration_of(input)
    result = remover.call(input)

    # Remove no translate and replace it with placeholders
    intermediary_html = result[:output].to_html

    # Undo removing
    output = filter(intermediary_html, {}, result)[:output].to_html

    refute_equal(input, intermediary_html)
    assert_equal(input, output)
  end

  def filter(text, context = {}, result = {})
    restorer.call(text, context, result)
  end

  def remover
    @remover ||= HTML::Pipeline.new([Localization::AzureTranslations::Filters::NoTranslateRemoverFilter])
  end

  def restorer
    @restorer ||= HTML::Pipeline.new([Localization::AzureTranslations::Filters::NoTranslateRestorerFilter])
  end
end
