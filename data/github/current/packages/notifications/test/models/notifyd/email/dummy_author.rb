# typed: strict
# frozen_string_literal: true

module Notifyd
  module Email
    class DummyAuthor

      include Author

      sig { override.returns(String) }
      def profile_name
        "John Doe"
      end
    end
  end
end
