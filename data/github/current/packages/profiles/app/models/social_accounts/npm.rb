# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Npm < SocialAccount
    recognize_with %r{https://(?:www\.)?npmjs\.com/~([^/?]+)/?}

    sig { override.returns(String) }
    def self.key
      "npm"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/profile-links/npm"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      url_match&.[](1)
    end
  end
end
