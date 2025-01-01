# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  module MessageBuilder
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.params(event: Event).returns(T.nilable(NotifyMessage)) }
    def build_message(event:); end
  end
end
