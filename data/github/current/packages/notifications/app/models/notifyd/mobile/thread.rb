# typed: true
# frozen_string_literal: true

module Notifyd
  module Mobile
    module Thread
      extend T::Helpers
      interface!

      sig { abstract.returns(T.nilable(String)) }
      def id; end

      sig { abstract.returns(String) }
      def type; end
    end
  end
end
