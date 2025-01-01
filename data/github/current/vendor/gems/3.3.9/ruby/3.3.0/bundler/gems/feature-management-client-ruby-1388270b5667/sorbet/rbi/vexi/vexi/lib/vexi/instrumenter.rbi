# frozen_string_literal: true
# typed: strict

module Vexi
  # Vexi instrumenter interface
  module Instrumenter
    extend T::Sig
    extend T::Helpers
    interface!

    include Kernel

    sig do
      abstract.params(_name: String, _payload: NotificationContext).void
    end
    def instrument(_name, _payload = {}); end
  end
end
