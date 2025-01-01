# typed: true
# frozen_string_literal: true

class Api::Internal::Twirp
  module Users
    module V1

      # Public: Generate the UserType enum for a user.
      #
      # user - A User
      #
      # Returns a Symbol.
      def self.user_type_enum(user)
        case user
        when Organization
          :USER_TYPE_ORGANIZATION
        when Bot
          :USER_TYPE_BOT
        when Mannequin
          :USER_TYPE_MANNEQUIN
        when User
          :USER_TYPE_USER
        else
          :USER_TYPE_INVALID
        end
      end

    end
  end
end
