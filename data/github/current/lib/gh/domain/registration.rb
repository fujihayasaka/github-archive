# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    module Registration
      extend T::Helpers

      requires_ancestor { Module }

      sig { params(domain_type: T.class_of(GH::Domain::Base), constructor: T.proc.returns(GH::Domain::Base)).void }
      def register_domain(domain_type, constructor = -> { domain_type.new })
        T.bind(self, Module)
        define_singleton_method(:domain) do
          GH.context.domain(self, constructor)
        end
        GH::Domain::Registration.registered_domains_map[self] = domain_type
      end

      sig { returns(T::Hash[Module, T.class_of(GH::Domain::Base)]) }
      def self.registered_domains_map
        @registered_domains_map ||= T.let({}, T.nilable(T::Hash[Module, T.class_of(GH::Domain::Base)]))
      end
    end
  end
end
