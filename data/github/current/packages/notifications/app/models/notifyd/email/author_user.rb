# typed: true
# frozen_string_literal: true

module Notifyd
  module Email
    # AuthorUser provides methods to fetch the necessary author information for
    # a user that is the author of a notification.
    class AuthorUser
      extend T::Sig
      include Author

      sig { params(user: ::User).void }
      def initialize(user:)
        @user = user
      end

      sig { override.returns(String) }
      def profile_name
        user.safe_profile_name
      end

      private

      sig { returns(::User) }
      attr_reader :user
    end
  end
end
