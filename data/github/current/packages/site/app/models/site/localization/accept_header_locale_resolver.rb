# typed: true
# frozen_string_literal: true

module Site::Localization
  class AcceptHeaderLocaleResolver
    def initialize(allowed_languages: Config.new.allowed_accept_language_headers)
      @allowed_languages = allowed_languages
    end

    # @return <String> the preferred user locale served at GitHub
    def resolve(header)
      candidates = AcceptLanguageHeaderParser.new.parse(header)
      candidates.find { |candidate| @allowed_languages.map(&:downcase).include?(candidate.downcase) } || "en-US"
    end
  end
end
