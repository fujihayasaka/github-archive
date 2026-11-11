# typed: strict
# frozen_string_literal: true

module SocialAccounts
  class Threads < SocialAccount
    recognize_with %r{https://(?:www\.)?threads\.(?:net|com)/(@[^/?]+)/?(?:\?.*)?}

    sig { override.returns(String) }
    def self.key
      "threads"
    end

    sig { override.returns(String) }
    def self.svg_path
      "site/icons/profile-links/threads"
    end

    sig { override.returns(String) }
    def self.title
      "Threads"
    end

    sig { override.returns(String) }
    def self.share_url
      "https://www.threads.com/intent/post"
    end

    sig { override.returns(T.nilable(String)) }
    def pretty_account_name
      match = url_match
      match[1] if match
    end
  end
end
