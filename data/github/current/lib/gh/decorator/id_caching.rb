# typed: true
# frozen_string_literal: true

module GH
  module Decorator
    module IdCaching
      extend GH::Decorator
      extend Scientist

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        raise "IdCaching can only be applied to GH::Domain::Base classes" unless decorable < GH::Domain::Base

        domain = GitHub.packageowners.package_for_type(decorable)
        accessor = T.cast(decorable, T.class_of(GH::Domain::Base)).accessor_name

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          next super(*args, **kwargs, &block) unless GH::Context.enabled? && GitHub.domain_interface_caching?

          cache = T.cast(self, GH::Domain::Base).cache

          id = args.first
          id = kwargs[:id] if id.nil?

          cache.fetch_by_id(id) do
            super(*args, **kwargs, &block)
          end
        end
      end
    end
  end
end
