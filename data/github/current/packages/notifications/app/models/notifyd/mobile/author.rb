# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    module Author
      extend T::Sig
      extend T::Helpers
      interface!

      sig { abstract.returns(String) }
      def avatar_url; end

      sig { abstract.returns(String) }
      def profile_name; end

      sig { abstract.returns(String) }
      def username; end
    end
  end
end
