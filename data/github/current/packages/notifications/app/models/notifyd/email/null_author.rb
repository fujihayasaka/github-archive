# typed: true
# frozen_string_literal: true

module Notifyd
  module Email
    class NullAuthor
      include Author

      sig { override.returns(String) }
      def profile_name
        ""
      end
    end
  end
end
