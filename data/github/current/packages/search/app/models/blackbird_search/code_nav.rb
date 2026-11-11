# typed: strict
# frozen_string_literal: true

module BlackbirdSearch
  class CodeNav
    # Public: Converts a language name to the format used by Blackbird's code nav feature flag format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. FeatureFlag.vexi.enabled?(:aleph_language_ruby)).
    sig { params(language_name: T.nilable(String)).returns(Symbol) }
    def self.convert_language_name(language_name)
      "aleph_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Converts a language name to the format used by Blackbird's darkship code nav feature flag format.
    #
    # language_name - language name to convert.
    #
    # Returns a symbol representing a feature flag (e.g. FeatureFlag.vexi.enabled?(:aleph_darkship_language_ruby)).
    sig { params(language_name: T.nilable(String)).returns(Symbol) }
    def self.convert_darkship_language_name(language_name)
      "aleph_darkship_language_#{clean_language_name(language_name)}".to_sym
    end

    # Public: Scrubs a Linguist language name to remove special symbols.
    #
    # language_name - language name to sanitize.
    #
    # Returns a sanitized string (e.g. Given "HTML+ERB" this method returns "html_erb").
    sig { params(language_name: T.nilable(String)).returns(T.nilable(String)) }
    def self.clean_language_name(language_name)
      return "csharp" if language_name == "C#"

      language_name&.gsub(INVALID_CHARS, "_")&.downcase
    end

    # Some characters are not valid for FeatureFlag.vexi names.
    # This regex is used to remove invalid characters from Linguist language names
    # when converting a Linguist language name to the derived format used with FeatureFlag.vexi.
    INVALID_CHARS = /[-+\s\.]/
  end
end
