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
      candidate = candidates.find { |c| @allowed_languages.map(&:downcase).include?(c.downcase) }
      return "en-US" if candidate.nil?

      # Return the properly-cased locale from @allowed_languages to ensure
      # consistency with Contentful's expected format (e.g., "pt-BR" not "pt-br")
      @allowed_languages.find { |lang| lang.downcase == candidate.downcase } || candidate
    end
  end
end
