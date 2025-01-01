# typed: true
# frozen_string_literal: true

module Nurture
  class SendgridData
    attr_reader :email, :display_login, :user_id, :unsub_url

    sig { params(email: T.nilable(String), display_login: T.nilable(String), user_id: T.nilable(Integer), unsub_url: T.nilable(String)).void }
    def initialize(email, display_login, user_id, unsub_url)
      @email = email
      @display_login = display_login
      @user_id = user_id
      @unsub_url = unsub_url
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_serialized_hash
      {
        email: email,
        display_login: display_login,
        user_id: user_id,
        unsub_url: unsub_url
      }
    end

    sig { params(hash: T::Hash[Symbol, T.untyped]).returns(SendgridData) }
    def self.from_serialized_hash(hash)
      new(hash[:email], hash[:display_login], hash[:user_id], hash[:unsub_url])
    end

    # This is used by assert_equal to compare two objects
    def ==(other)
      other.is_a?(self.class) &&
        other.email == email &&
        other.display_login == display_login &&
        other.user_id == user_id &&
        other.unsub_url == unsub_url
    end
  end
end
