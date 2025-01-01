# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class LinkedIn < SocialAccount
    recognize_with %r{https://(?:www\.)?linkedin\.com/(?:in|company)/[^/?]+/?}

    sig { override.returns(String) }
    def self.key
      "linkedin"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/profile-links/linkedin"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url.gsub(%r{\Ahttps://(?:www\.)?linkedin\.com/}, "").gsub(%r{/\z}, "")
    end
  end
end
