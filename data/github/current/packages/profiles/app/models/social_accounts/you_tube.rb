# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class YouTube < SocialAccount
    recognize_with %r{https://(?:www\.)?youtube\.com/(user|c)/[^/?]+/?},
      %r{https://(?:www\.)?youtube\.com/channel/[a-zA-Z0-9_-]{24}/?},
      %r{https://(?:www\.)?youtube\.com/@[^/?]+/?}

    sig { override.returns(String) }
    def self.key
      "youtube"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/youtube"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url.gsub(%r{\Ahttps://(?:www\.)?youtube\.com/}, "").gsub(%r{/\z}, "")
    end
  end
end
