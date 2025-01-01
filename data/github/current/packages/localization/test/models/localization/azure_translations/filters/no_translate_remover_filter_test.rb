# typed: true
# frozen_string_literal: true

require_relative "../../../../fast_test_helper"

class Localization::AzureTranslations::Filters::NoTranslateRemoverRemoverFilterTest < GitHub::TestCase
  setup do
    SecureRandom.stubs(:uuid).returns("uid1", "uid2", "uid3", "uid4")
  end

  test "it ignores any text that is not really html" do
    input = 'This is a random text with no id="something" attributes'
    expected = input

    assert_equal expected, filter(input)[:output].to_html
  end

  test "it replaces no-translate with placeholders and keeps track of replaced contents" do
    input = <<~HTML
      <div id="the-div">
        <p class="foo notranslate"><span>DONT ONE</span></p>
        <p>Hi there</p>
        <p class="notranslate">DONT TWO</p>
        <p>Hi there again</p>
        <p class="notranslate">DONT THREE <span class="notranslate">DONT FOUR</span></p>
      </div>
    HTML

    expected = <<~HTML
      <div id="the-div">
        <p class="foo notranslate"><span id="tph_uid1"></span></p>
        <p>Hi there</p>
        <p class="notranslate"><span id="tph_uid2"></span></p>
        <p>Hi there again</p>
        <p class="notranslate"><span id="tph_uid3"></span></p>
      </div>
    HTML

    result = filter(input)

    assert_equal(expected, result[:output].to_html)

    expected_context = {
      "tph_uid1" => "<span>DONT ONE</span>",
      "tph_uid2" => "DONT TWO",
      "tph_uid3" => 'DONT THREE <span class="notranslate">DONT FOUR</span>',
      "tph_uid4" => "DONT FOUR"
    }

    assert_equal(expected_context, result[:removed_no_translate])
  end

  test "it replaces no-translate content including newlines with placeholders and keeps track of replaced contents" do
    input = <<~HTML
      <div id="the-div">
        <p class="foo notranslate"><span>DONT ONE</span></p>
        <p>Hi there</p>
        <div class="notranslate">
          <div>
            <p>Here is a silly function:</p>
            <p><span>function sayHello(greeting) {</span></p>
            <p><span>console.log('greeting')</span></p>
            <p><span>}</span></p>
          </div>
        </div>
      </div>
    HTML

    expected = <<~HTML
      <div id="the-div">
        <p class="foo notranslate"><span id="tph_uid1"></span></p>
        <p>Hi there</p>
        <div class="notranslate"><span id="tph_uid2"></span></div>
      </div>
    HTML

    result = filter(input)

    assert_equal(expected, result[:output].to_html)
  end

  private

  def filter(text)
    pipeline.call(text)
  end

  def pipeline
    @pipeline ||= HTML::Pipeline.new([Localization::AzureTranslations::Filters::NoTranslateRemoverFilter])
  end
end
