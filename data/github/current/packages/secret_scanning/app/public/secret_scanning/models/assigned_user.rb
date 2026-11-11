# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    # This class gets used for normal (not assignee related) user stuff like `current_user`
    # on the show page. Renaming this class to `User` causes namespace collisions, meaning we'd
    # have to rename all our usages of the base `User` class to `::User`. For now, this will stay
    # as the not as accurate `AssignedUser` name.
    class AssignedUser < T::Struct
      const :id, Integer
      const :display_login, String
      const :email, String
      const :profile_name, T.nilable(String)
      const :avatar_url, String
      const :is_copilot, T::Boolean, default: false

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::AssignedUser)) }
      def self.from_token(token)
        user = token.assigned_user
        return nil if user.nil?
        from_user(user)
      end

      sig { params(user: User).returns(SecretScanning::Models::AssignedUser) }
      def self.from_user(user)
        new(
          id: user.id,
          display_login: user.display_login,
          email: user.email,
          profile_name: user.profile_name,
          avatar_url: user.primary_avatar_url(64),
          is_copilot: false,
        )
      end

      sig { override.params(args: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
      def serialize(args)
        serialize_ui
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def serialize_ui
        {
          id:,
          login: display_login,
          userEmail: email,
          name: profile_name,
          avatarUrl: avatar_url,
          isCopilot: is_copilot,
        }
      end
    end
  end
end
