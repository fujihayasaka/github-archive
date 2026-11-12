# typed: strict
# frozen_string_literal: true

require_relative "registration"

module OctoCore
  module Domain
    class Base
      extend T::Sig
      extend T::Helpers
      extend OctoCore::Decorator::Decorable

      abstract!

      sig { params(actor: T.nilable(Auth::Actor)).void }
      def initialize(actor: nil)
        self.class.apply_decorators!
        @actor_override = actor # used instead of the identity context domain actor when present
      end

      sig { returns(T.nilable(Auth::Actor)) }
      def actor
        @actor_override || OctoCore.identity_context.domain_actor
      end

      @_accessor_name = T.let(nil, T.nilable(String))

      sig { returns(OctoCore::Domain::Cache) }
      def cache
        @cache ||= T.let(
          OctoCore::Domain::Cache.new(
            domain: "undefined",
            accessor: T.must(self.class.name)
          ), T.nilable(OctoCore::Domain::Cache)
        )
      end
    end
  end
end
