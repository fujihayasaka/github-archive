# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class Localization::AzureTranslations::SplitResultTest < GitHub::TestCase
  test "#join joins frame and fragments" do
    frame = <<~HTML
      <div>
        <span data-tph="foo"></span>
        <span data-tph="bar"></span>
      </div>
    HTML

    fragment = <<~HTML
      <div>
        <span data-tph="bar">Hi I am bar.</span>
        <p data-tph="foo">Hi I am foo</p>
        <p data-tph="baz">Don't care</p>
      </div>
    HTML

    expected = <<~HTML
      <div>
        <p>Hi I am foo</p>
        <span>Hi I am bar.</span>
      </div>
    HTML

    result = create(frame, [fragment])

    assert_same_html expected, result.join
  end

  test "#translation" do
    client = GitHub::Azure::TranslatorClient.new(subscription_key: "x", region: "y")

    frame = '<div><span data-tph="foo"></span></div>'
    fragment = '<div><p data-tph="foo">FOO</p></div>'

    client.expects(:translate).with(frame, from: "en", to: "pt")
      .returns(create_api_response(frame))

    client.expects(:translate).with(fragment, from: "en", to: "pt")
      .returns(create_api_response(fragment.sub(/FOO/, "FOO_TRANSLATED")))

    result = create(frame, [fragment, ""])

    translation = result.translate(
      from: "en",
      to: "pt",
      translation_client: client
    )

    assert_same_html "<div><p>FOO_TRANSLATED</p></div>", translation.join
  end

  private

  def create(frame, fragments)
    Localization::AzureTranslations::SplitResult.new(frame, fragments)
  end

  def assert_same_html(expected, actual)
    assert_equal(normalize_html(expected), normalize_html(actual))
  end

  def normalize_html(html)
    html.to_s.gsub(/^\s+</, "<").gsub(/></, ">\n<").strip
  end

  def create_api_response(*translations)
    api_response = [
      {
        translations: translations.map { |text| { text: text } }
      }
    ]
  end
end
