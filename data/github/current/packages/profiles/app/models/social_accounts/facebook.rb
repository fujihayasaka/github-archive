# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Facebook < SocialAccount
    recognize_with %r{https://(?:[^.]+\.)?facebook\.com/(?:[^/?]+/?|profile\.php\?id=\d+)}

    sig { override.returns(String) }
    def self.key
      "facebook"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/facebook"
    end

    sig { override.returns(String) }
    def self.share_url
      "https://facebook.com/sharer/sharer.php"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url.gsub(%r{\Ahttps://(?:www\.|web\.|m\.)?facebook.com/}, "").gsub(%r{/\z}, "")
    end
  end
end
