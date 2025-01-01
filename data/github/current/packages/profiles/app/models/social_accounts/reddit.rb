# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Reddit < SocialAccount
    recognize_with %r{https://(?:www\.)?reddit\.com/u(?:ser)?/([^/?]+)/?}

    sig { override.returns(String) }
    def self.key
      "reddit"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/reddit"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      match = url_match
      "u/#{match[1]}" if match
    end
  end
end
