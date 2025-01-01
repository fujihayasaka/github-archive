# typed: true
# frozen_string_literal: true

module Localization
  class AcceptLanguageHeaderParser
    # It returns an array of accept languages sorted by priority
    #
    # Sort of taken from https://github.com/mperham/sidekiq/blob/3b5ae30c4e5e9e760268243ab5c14664a2f8d236/lib/sidekiq/web/helpers.rb
    # @see https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language
    def parse(accept_header_string)
      accept_header_string.to_s.sub(/\s+/, "").split(",").map do |language|
        locale, quality = language.split(";q=", 2)
        locale = nil if locale == "*" # Ignore wildcards
        quality = quality ? quality.to_f : 1.0
        [locale, quality]
      end.sort do |(_, left), (_, right)|
        right <=> left
      end.map(&:first).compact
    end
  end
end
