# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Twitch < SocialAccount
    recognize_with %r{https://(?:www\.)?twitch\.tv/[^/?]+/?}

    sig { override.returns(String) }
    def self.key
      "twitch"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/twitch"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url.gsub(%r{\Ahttps://(?:www\.)?twitch\.tv/}, "").gsub(%r{/\z}, "")
    end
  end
end
