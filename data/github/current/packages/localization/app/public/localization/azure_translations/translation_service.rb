# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  module AzureTranslations
    # DEPRECATED: This service is being phased out and should no longer be used.
    # The Azure Translator integration is being deprecated since we no longer subscribe to the Azure service.
    #
    # When the :deprecate_translation_service feature flag is enabled, this service will return
    # safe default values without making any external API calls.
    class TranslationService
      def initialize(
        http_client: GitHub::Azure::TranslatorClient.new,
        html_splitter: HtmlSplitter.new,
        pre_translation_pipeline: PreTranslationPipeline.new,
        post_translation_pipeline: PostTranslationPipeline.new
      )
        @client = http_client
        @html_splitter = html_splitter
        @pre_translation_pipeline = pre_translation_pipeline
        @post_translation_pipeline = post_translation_pipeline
      end

      # It detecs the language of a text based on the language of the first 50k chars.
      #
      # DEPRECATED: Returns nil when translation service is deprecated via feature flag.
      def detect_language(text)
        # Early return if translation service is deprecated - prevents Azure API calls
        return nil if FeatureFlag.vexi.enabled?(:deprecate_translation_service, default: false)

        modified_text = @pre_translation_pipeline.call(text)[:output].to_s
        result = @html_splitter.split(modified_text)
        modified_text = result.pieces[0..1].last

        handle_errors do
          data = @client.detect_language(modified_text)
          data.dig(0, :language)
        end
      end

      # DEPRECATED: Returns empty string when translation service is deprecated via feature flag.
      def translate(text, to:, from: nil)
        # Early return if translation service is deprecated - prevents Azure API calls
        return "" if FeatureFlag.vexi.enabled?(:deprecate_translation_service, default: false)

        result = @pre_translation_pipeline.call(text)
        modified_text = result[:output].to_s

        html = handle_errors do
          split_result = @html_splitter.split(modified_text)
          split_result.translate(translation_client: @client, from: from, to: to).join
        end

        @post_translation_pipeline.call(html, {}, result)[:output].to_s
      end

      private

      def handle_errors
        yield
      rescue Faraday::Error => error
        raise HttpError.new(error)
      end
    end
  end
end
