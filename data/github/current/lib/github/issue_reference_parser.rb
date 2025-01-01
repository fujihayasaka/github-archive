# typed: true
# frozen_string_literal: true

module GitHub
  module IssueReferenceParser
    include GitHub::Memoizer

    extend self
    # Example: github/github, rails
    NAME_OR_NWO = /(?<name_or_nwo>(?:\w+(?:-\w+)*(?:\/[.\w-]+)?))/.freeze

    # Example: "#", "gh-", "/issues/"
    MARKER = %r<(?<marker>#|gh-|/(?:issues|pull|discussions)/)(?=\d)>i.freeze
    NUMBER = /(?<number>\d+)\b/.freeze

    # Matches only strings that are issue anchors and do not contain any additional characters:
    # text github/github#1 text - will not be matched
    # github/github#1 - will be matched
    ISSUE_REFERENCE = %r{^(?<full_reference>(#{NAME_OR_NWO})?#{MARKER}#{NUMBER})$}.freeze

    GITHUB_URL = %r{#{Regexp.escape(GitHub.scheme + "://github.com")}}.freeze

    def parse_references(references)
      return [] unless references
      references.map { |ref| parse_reference(ref) }
    end

    # Turn issue reference into a data structure
    def parse_reference(reference)
      if is_valid_github_url?(reference)
        parse_url_reference(reference)
      else
        parse_nwo_reference(reference)
      end
    end

    def parse_nwo_reference(reference)
      reference.to_s.match(ISSUE_REFERENCE) do |match|
        nwo = match[:name_or_nwo]
        number = match[:number]
        { nwo: nwo, number: number }
      end
    end

    def parse_url_reference(reference)
      sanitized_url = sanitize_url(reference)
      match = sanitized_url.match(full_url_issue_mention)
      return unless match

      nwo = match[:name_or_nwo]
      number = match[:number]
      { nwo: nwo, number: number }
    end

    private

    # Returns true if the param `url` is a valid github url.
    # For reference - https://github.com/github/security-docs/blob/master/standards/Secure%20Coding%20Principles.md#good-for-both-addressableuri-or-uri
    def is_valid_github_url?(url)
      begin
        parsed = URI.parse(url)
        valid_github_host = if GitHub.multi_tenant_enterprise?
          parsed.host&.include?(GitHub.host_domain) || parsed.host&.include?(GitHub.host_name)
        else
          [GitHub.host_domain, GitHub.host_name].include?(parsed.host)
        end

        valid_github_host && parsed.scheme == GitHub.scheme
      rescue URI::InvalidURIError
        false
      end
    end

    # Returns a sanitized url by clearing any portion of the parsed URL that we is not expected in a valid request.
    # For reference - https://github.com/github/security-docs/blob/master/standards/Secure%20Coding%20Principles.md#good-for-both-addressableuri-or-uri
    def sanitize_url(url)
      parsed = Addressable::URI.parse(url)
      parsed.userinfo = nil
      parsed.fragment = nil
      parsed.normalize.to_s
    end

    memoize def full_url_issue_mention
      current_url = %r{#{Regexp.escape(GitHub.url)}}.freeze
      %r<^(#{current_url}|#{GITHUB_URL})/#{NAME_OR_NWO}/(?:issues|pull)/#{NUMBER}(#[\w-]+)?\b$>.freeze
    end
  end
end
