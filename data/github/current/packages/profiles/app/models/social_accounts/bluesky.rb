# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Bluesky < SocialAccount
    recognize_with %r{https://bsky\.app/profile/([^@/]+)/?}

    sig { override.returns(String) }
    def self.key
      "bluesky"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/bluesky"
    end

    sig { returns(T.nilable(String)) }
    def username
      match = url_match
      match[1] if match
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      "@#{username}" if username
    end
  end
end
