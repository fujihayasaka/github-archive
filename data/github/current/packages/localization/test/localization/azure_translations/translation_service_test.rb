# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class Localization::AzureTranslations::TranslationServiceTest < GitHub::TestCase
  setup do
    @http_client = GitHub::Azure::TranslatorClient.new(
      subscription_key: "the-key",
      region: "the-region",
    )
    @service = Localization::AzureTranslations::TranslationService.new(http_client: @http_client)
  end

  test "it detects language" do
    @http_client.expects(:detect_language).with("text").returns([{ language: "en" }])

    assert_equal "en", @service.detect_language("text")
  end

  test "it translates to a language" do
    api_response = [
      {
        detectedLanguage: { language: "en", score: 1.0 },
        translations:  [{ text: "Olá", to: "pt" }]
      }
    ]

    @http_client.expects(:translate).with("hello", to: "pt", from: nil).returns(api_response)

    assert_equal "Olá", @service.translate("hello", to: "pt")
  end

  test "it translates to a language from another language" do
    api_response = [
      {
        detectedLanguage: { language: "en", score: 1.0 },
        translations:  [{ text: "Olá", to: "pt" }]
      }
    ]

    @http_client.expects(:translate).with("hello", to: "pt", from: "en").returns(api_response)

    assert_equal "Olá", @service.translate("hello", to: "pt", from: "en")
  end

  test "filters are applyed before translation" do
    api_response = [{ translations:  [{ text: "Olá" }] }]

    @http_client.expects(:translate).with("<p>hello</p>", to: "pt", from: "en").returns(api_response)

    assert_equal "Olá", @service.translate('<p id="hello">hello</p>', to: "pt", from: "en")
  end

  test "correctly decodes encoded unsafe characters" do
    api_response = [{ translations:  [{ text: "Hello, how are you? &#65308img src=\"x\" onerror=alert(1)&#65310" }] }]

    @http_client.expects(:translate).with("Hallo, wie geht es Ihnen? ＜img src=\"x\" onerror=alert(1)＞", to: "en", from: "de").returns(api_response)

    assert_equal "Hello, how are you? ＜img src=\"x\" onerror=alert(1)＞", @service.translate('Hallo, wie geht es Ihnen? ＜img src="x" onerror=alert(1)＞', to: "en", from: "de")
  end

  test "handles Faraday::Error" do
    body = '{"error":{"code":400036,"message":"The target language is not valid."}}'
    response = stub(body: body, status: 500)
    error = Faraday::Error.new("message", response)

    @http_client.expects(:detect_language).with("text").raises(error)

    raised_error = assert_raises(Localization::AzureTranslations::TranslationService::Error) do
      @service.detect_language("text")
    end

    assert_equal "The target language is not valid.", raised_error.message
  end
end
