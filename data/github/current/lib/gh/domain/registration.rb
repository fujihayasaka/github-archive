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
        GH::Domain::Registration.registered_domain_methods[self] = domain_type
        GH::Domain::Registration.registered_domains_map[self] = domain_type
      end

      sig do
        params(
          domain_class: T.class_of(GH::Domain::Base),
          accessor_class: T.class_of(GH::Domain::Base),
          accessor_name: Symbol
        ).void
      end
      def self.register_domain_accessor(domain_class, accessor_class, accessor_name)
        constructor = -> { accessor_class.new }
        domain_class.define_method(accessor_name) do
          GH.context.domain(accessor_class, constructor)
        end
        GH::Domain::Registration.registered_domains_map[accessor_class] = accessor_class
      end

      sig { returns(T::Hash[Module, T.class_of(GH::Domain::Base)]) }
      def self.registered_domains_map
        @registered_domains_map ||= T.let({}, T.nilable(T::Hash[Module, T.class_of(GH::Domain::Base)]))
      end

      # for tapioca compiler
      sig { returns(T::Hash[Module, T.class_of(GH::Domain::Base)]) }
      def self.registered_domain_methods
        @registered_domains_methods ||= T.let({}, T.nilable(T::Hash[Module, T.class_of(GH::Domain::Base)]))
      end

      sig { params(domain: T.class_of(GH::Domain::Base)).returns(T.nilable(Module)) }
      def self.registered_namespace_for(domain)
        registered_domains_map.key(domain)
      end

      sig { params(namespace: Module).returns(T::Array[GH::Domain::Base]) }
      def self.all_domains_for(namespace)
        GH::Context.send(:stack).map do |context|
          context.send(:domain_map).collect { |_, domains| domains[namespace] }.compact
        end.flatten
      end
    end
  end
end
