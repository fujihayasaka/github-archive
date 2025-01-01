# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Twitter < SocialAccount
    recognize_with %r{https://(?:www\.)?(?:twitter|x)\.com/([^/?]+)/?}

    sig { override.returns(String) }
    def self.key
      "twitter"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/twitter-x"
    end

    sig { override.returns(String) }
    def self.title
      "X"
    end

    sig { override.returns(T::Boolean) }
    def self.twitter?
      true
    end

    sig { returns(T.nilable(String)) }
    def username
      match = url_match
      return unless match
      # Remove the `@` if the user included it in the URL
      match[1]&.gsub(/\A@/, "")&.strip
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      "@#{username}" if username
    end
  end
end
