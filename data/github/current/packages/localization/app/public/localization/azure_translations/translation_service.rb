# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  module AzureTranslations
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
      def detect_language(text)
        modified_text = @pre_translation_pipeline.call(text)[:output].to_s
        result = @html_splitter.split(modified_text)
        modified_text = result.pieces[0..1].last

        handle_errors do
          data = @client.detect_language(modified_text)
          data.dig(0, :language)
        end
      end

      def translate(text, to:, from: nil)
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
        Failbot.report(error)
        raise HttpError.new(error)
      end
    end
  end
end
