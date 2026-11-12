# typed: strict
# frozen_string_literal: true

module OctoCore
  module Auth
    module IdentityContext
      class ValueContext
        extend T::Sig
        include IdentityContext

        sig { params(actor: T.nilable(Actor)).void }
        def initialize(actor = nil)
          @domain_actor = actor
        end

        sig { override.returns(T.nilable(Actor)) }
        attr_reader :domain_actor
      end
    end
  end
end
