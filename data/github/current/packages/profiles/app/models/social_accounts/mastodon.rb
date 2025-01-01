# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Mastodon < SocialAccount
    ACCOUNT_PATTERN = T.let(%r{https?://([^/]+)/@([^/?]+)/?}, Regexp)
    recognize_with ACCOUNT_PATTERN, nodeinfo: "mastodon"

    sig { override.returns(String) }
    def self.key
      "mastodon"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/mastodon"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      match = url_match
      "@#{match[2]}@#{match[1]}" if match
    end

    sig { override.returns(T::Boolean) }
    def self.mastodon?
      true
    end
  end
end
