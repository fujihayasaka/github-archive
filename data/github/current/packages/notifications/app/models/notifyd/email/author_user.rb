# typed: true
# frozen_string_literal: true

module Notifyd
  module Email
    # AuthorUser provides methods to fetch the necessary author information for
    # a user that is the author of a notification.
    class AuthorUser
      include Author

      sig { params(user: ::User).void }
      def initialize(user:)
        @user = user
      end

      sig { override.returns(String) }
      def profile_name
        @user.safe_profile_name
      end

      sig { override.returns(T.nilable(User)) }
      def user
        @user
      end
    end
  end
end
