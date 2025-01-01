# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Localization
  module Test
    class MockConfig
      def initialize
        @ugct_languages = []
        with_languages("en" => "English", "pt" => "Portuguese")
        with_ugct_languages(%w[pt en ko])
      end

      def with_primary_browser_language(language_with_locale)
        @primary_browser_language = language_with_locale.to_s
        self
      end

      def primary_browser_language
        @primary_browser_language || raise("primary_browser_language not defined")
      end

      def primary_browser_language_without_region
        primary_browser_language.split("-").first
      end

      def primary_browser_language_name
        language_name(primary_browser_language_without_region)
      end

      def language_name(code)
        @languages.fetch(code)
      end

      def with_languages(languages)
        @languages = languages
        self
      end

      def with_ugct_languages(languages)
        languages.each do |language|
          with_ugct_language(language)
        end
        self
      end

      def with_ugct_language(other_language)
        @ugct_languages.push(other_language)
        self
      end

      def ugct_supports_language?(language)
        @ugct_languages.include?(language)
      end

      def with_ugct_banner_enabled(enabled = true)
        @ugct_banner_enabled = enabled
        self
      end

      def ugct_banner_enabled?
        @ugct_banner_enabled
      end
    end
  end
end
