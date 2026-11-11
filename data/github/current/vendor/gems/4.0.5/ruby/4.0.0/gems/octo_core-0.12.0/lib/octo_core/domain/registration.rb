# typed: strict
# frozen_string_literal: true

module OctoCore
  module Domain
    module Registration
      extend T::Sig
      extend T::Helpers

      requires_ancestor { Module }

      sig { params(domain_type: T.class_of(OctoCore::Domain::Base), constructor: T.proc.returns(OctoCore::Domain::Base)).void }
      def register_domain(domain_type, constructor = -> { domain_type.new })
        T.bind(self, T::Module[T.anything])
        define_singleton_method(:domain) do
          OctoCore.context.domain(self, constructor)
        end
        OctoCore::Domain::Registration.registered_domains_map[self] = domain_type
      end

      sig { returns(T::Hash[T::Module[T.anything], T.class_of(OctoCore::Domain::Base)]) }
      def self.registered_domains_map
        @registered_domains_map ||= T.let({}, T.nilable(T::Hash[T::Module[T.anything], T.class_of(OctoCore::Domain::Base)]))
      end
    end
  end
end
