# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    class NullAuthor
      include Author

      sig { override.returns(String) }
      def avatar_url
        ""
      end

      sig { override.returns(String) }
      def profile_name
        ""
      end

      sig { override.returns(String) }
      def username
        ""
      end
    end
  end
end
