# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Hometown < Mastodon
    recognize_with ACCOUNT_PATTERN, nodeinfo: "hometown"

    sig { override.returns(String) }
    def self.key
      "hometown"
    end
  end
end
