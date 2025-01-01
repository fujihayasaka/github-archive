# frozen_string_literal: true
# typed: strict

module Vexi
  module Observability
    # Vexi null notifications instrumenter
    class Null
      extend T::Sig
      extend T::Helpers

      include Instrumenter

      sig do
        override.params(_name: String, _payload: Instrumenter::NotificationContext).void
      end
      def instrument(_name, _payload = {}); end
    end
  end
end
