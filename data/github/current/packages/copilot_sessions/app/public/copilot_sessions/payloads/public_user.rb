# typed: strict
# frozen_string_literal: true

# Only include publicly accessible user data
module CopilotSessions
  module Payloads
    class PublicUser
      sig { returns(User) }
      attr_reader :user

      sig { params(user: User).void }
      def initialize(user)
        @user = user
      end

      class UserHash < T::Struct
        prop :id, Integer
        prop :login, String
        prop :primaryAvatarUrl, String
      end

      sig { returns(UserHash) }
      def call
        UserHash.new(
          id: user.id,
          login: user.display_login,
          primaryAvatarUrl: user.primary_avatar_url,
        )
      end
    end
  end
end
