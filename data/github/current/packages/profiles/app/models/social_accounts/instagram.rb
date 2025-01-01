# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Instagram < SocialAccount
    recognize_with %r{https://(www\.)?instagram\.com/[^/?]+/?}

    sig { override.returns(String) }
    def self.key
      "instagram"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/profile-links/instagram"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url.gsub(%r{\Ahttps://(www\.)?instagram\.com/}, "").gsub(%r{/\z}, "")
    end
  end
end
