# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class DummyAuthor
      extend T::Sig

      include Author

      sig { override.returns(String) }
      def avatar_url
        "http://alambic.github.test/avatars/u/1?b=1&v=2"
      end

      sig { override.returns(String) }
      def profile_name
        "John Doe"
      end

      sig { override.returns(String) }
      def username
        "john_doe"
      end
    end
  end
end
