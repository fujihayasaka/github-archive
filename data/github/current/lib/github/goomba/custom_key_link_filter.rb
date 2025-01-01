# typed: true
# frozen_string_literal: true

#
module GitHub::Goomba
  class CustomKeyLinkFilter < TextFilter
    SELECTOR = Goomba::Selector.new(match: ":text", reject: "pre :text, code :text, a :text, blockquote :text")

    def self.cache_key(context)
      return unless context[:entity].is_a?(Repository)
      Repositories.domain.key_links.cache_key(context[:entity].id)
    end

    def self.feature_flags
      [
        # used in `.cache_key`
        # add any new FFs here
      ]
    end

    def self.enabled?(context)
      return false unless context[:entity].is_a?(Repository)
      repository = context[:entity]
      GitHub::Result.new { Repositories.domain.key_links.custom_key_links_active?(repository.id) && repository.plan_supports?(:custom_key_links) }.value { false }
    end

    def selector
      SELECTOR
    end

    # Lookbehind to ensure that keys are either at the beginning of a
    # line or preceded by non-alpha-numeric character (space, parenthesis,
    # period, comma, etc.).
    KEY_LEAD_RE = %r{(?<=\b)}

    # Lookahead to ensure that keys are either at the end of a line or
    # followed by non-alpha-numeric character (space, parenthesis, period,
    # comma, etc.).
    ALPHA_KEY_TAIL_RE = %r{(?![\\w\\-])}
    NON_ALPHA_KEY_TAIL_RE = %r{(?=\b)}

    def call(text)
      content = text.html

      alphanumeric_links = []
      non_alphanumeric_links = []
      object = {}

      key_links = GitHub::Result.new { Repositories.domain.key_links.list_for_repo(repository.id) }.value { [] }.to_a
      key_links.each do |key_link|
        if key_link.is_alphanumeric?
          alphanumeric_links << Regexp.escape(key_link.key_prefix)
        else
          non_alphanumeric_links << Regexp.escape(key_link.key_prefix)
        end

        object[key_link.key_prefix.downcase] = key_link
      end

      # Construct regex with two capture groups to match key and number
      if alphanumeric_links.any?
        re_str = "#{KEY_LEAD_RE}((#{alphanumeric_links.join('|')})([\\da-z\\-]+))#{ALPHA_KEY_TAIL_RE}"
        regex = Regexp.new(re_str, Regexp::IGNORECASE)

        content = replace_keys(content, object, regex)
      end

      if non_alphanumeric_links.any?
        re_str = "#{KEY_LEAD_RE}((#{non_alphanumeric_links.join('|')})(\\d+))#{NON_ALPHA_KEY_TAIL_RE}"
        regex = Regexp.new(re_str, Regexp::IGNORECASE)

        content = replace_keys(content, object, regex)
      end

      content
    end

    private

    def replace_keys(content, object, regex)
      # Replace all keys that match the pattern
      content.gsub!(regex) do |match|
        matched_fullid = $1
        matched_prefix = $2
        matched_number = $3

        match = object[matched_prefix.downcase]
        return content unless match

        url = match.url(matched_number)

        # Abort all processing if we detect a single invalid URL
        return content unless URI::ABS_URI.match?(url)

        attrs = {
          "class"      => "issue-link js-issue-link notranslate",
          "rel"        => "noopener noreferrer nofollow",
        }

        GitHub.dogstats.increment("key_links", tags: ["action:linked"])
        ActionController::Base.helpers.link_to(matched_fullid, url, attrs)
      end

      content
    end
  end
end
