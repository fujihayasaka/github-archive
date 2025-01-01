# frozen_string_literal: true
# typed: strict

module Vexi
  module Observability
    # Vexi activesupport notifications instrumenter
    class Notification
      extend T::Sig
      extend T::Helpers

      include Instrumenter

      sig do
        override.params(name: String, payload: NotificationContext).void
      end
      def instrument(name, payload = {}); end
    end
  end
end
