# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module Notifyd::NewIntegrator
  module Serializable
    extend T::Sig
    extend T::Helpers

    interface!

    sig { abstract.returns(T.untyped) }
    def as_serializable; end
  end
end
