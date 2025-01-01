# typed: true
# frozen_string_literal: true

# A simple client for the Azure Cognitive Services' Translator API
#
# @see https://docs.microsoft.com/en-us/azure/cognitive-services/translator/
module GitHub
  module Azure
    class TranslatorClient
      TranslationArrayLimitError = Class.new(RuntimeError)

      AZURE_TRANSATOR_URL = "https://api.cognitive.microsofttranslator.com"
      # https://docs.microsoft.com/en-us/azure/cognitive-services/translator/request-limits#character-and-array-limits-per-request
      TRANSLATION_ARRAY_LIMIT = 1_000

      # Unsafe characters and their replacements.
      # See https://github.com/github/helphub/issues/2543
      UNSAFE_CHARACTERS = {
        "＜" => "&#65308",
        "＞" => "&#65310",
        "﹤" => "&#65124",
        "﹥" => "&#65125",
      }.freeze
      UNSAFE_CHARACTERS_REGEX = Regexp.union(UNSAFE_CHARACTERS.keys)

      def initialize(
        subscription_key: GitHub.azure_translator_subscription_key,
        region: GitHub.azure_translator_subscription_region
      )
        @http_client = HttpClient.new
        @subscription_key = subscription_key
        @region = region
      end

      def detect_language(text)
        post("detect", body: [{ text: text }])
      end

      def translate(text_or_texts, to:, from: nil)

        texts = Array.wrap(text_or_texts)

        if texts.length > TRANSLATION_ARRAY_LIMIT
          raise TranslationArrayLimitError
        end

        params = { to: to, from: from, textType: "html" }.compact_blank
        body = texts.map { |text| { text: remove_unsafe_characters(text) } }
        post("translate", body: body, query_params: params)
      end

      private

      def post(endpoint, body: [], query_params: {})
        if @subscription_key.blank?
          GitHub.logger.info("Missing Azure Translator subscription key. To enable, set the AZURE_TRANSLATOR_SUBSCRIPTION_KEY environment variable.")
          return []
        end

        uri = URI.parse("#{AZURE_TRANSATOR_URL}/#{endpoint}")

        response = @http_client.send_request(
          method: :post,
          uri: uri.to_s,
          params: { "api-version": "3.0" }.merge(query_params),
          headers: headers,
          body: body
        )

        response.body
      end

      def headers
        {
          "Ocp-Apim-Subscription-Key": @subscription_key,
          "Ocp-Apim-Subscription-Region": @region,
          "X-ClientTraceId": SecureRandom.uuid
        }
      end

      def remove_unsafe_characters(text)
        # Ensure text does not contain any unsafe characters like ＜ or ＞
        # https://github.com/github/special-projects/issues/1148

        text.gsub(UNSAFE_CHARACTERS_REGEX, UNSAFE_CHARACTERS)
      end
    end
  end
end
