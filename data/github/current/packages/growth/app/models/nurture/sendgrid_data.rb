# typed: true
# frozen_string_literal: true

module Nurture
  class SendgridData
    attr_reader :email, :display_login, :unsub_url

    sig { params(email: T.nilable(String), display_login: T.nilable(String), unsub_url: T.nilable(String)).void }
    def initialize(email, display_login, unsub_url)
      @email = email
      @display_login = display_login
      @unsub_url = unsub_url
    end

    sig { returns(T::Hash[Symbol, T.nilable(String)]) }
    def to_serialized_hash
      {
        email: email,
        display_login: display_login,
        unsub_url: unsub_url
      }
    end

    sig { params(hash: T::Hash[Symbol, T.nilable(String)]).returns(SendgridData) }
    def self.from_serialized_hash(hash)
      new(hash[:email], hash[:display_login], hash[:unsub_url])
    end

    # This is used by assert_equal to compare two objects
    def ==(other)
      other.is_a?(self.class) &&
        other.email == email &&
        other.display_login == display_login &&
        other.unsub_url == unsub_url
    end
  end
end
