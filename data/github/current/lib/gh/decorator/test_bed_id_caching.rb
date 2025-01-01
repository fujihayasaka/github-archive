# typed: true
# frozen_string_literal: true

module GH
  module Decorator
    module TestBedIdCaching
      extend GH::Decorator
      extend Scientist

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        raise "TestBedIdCaching can only be applied to GH::Domain::Base classes" unless decorable < GH::Domain::Base

        domain = GitHub.packageowners.package_for_type(decorable)
        accessor = T.cast(decorable, T.class_of(GH::Domain::Base)).accessor_name
        # domain_id_caching_repositories_repositories_by_id
        test_name = "domain_id_caching_#{domain&.gsub("packages/", "")}_#{accessor}_#{method_name}"
        flipper_name = test_name.to_sym

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          next super(*args, **kwargs, &block) unless GH::Context.enabled? && GitHub.domain_interface_caching?

          cache = T.cast(self, GH::Domain::Base).cache

          feature_enabled = GH.identity_context.domain_actor&.feature_enabled?(flipper_name)
          feature_enabled = GitHub.flipper[flipper_name].enabled? if feature_enabled.nil?

          id = args.first
          id = kwargs[:id] if id.nil?

          if feature_enabled
            cache.fetch_by_id(id) do
              super(*args, **kwargs, &block)
            end
          else
            control = super(*args, **kwargs, &block)
            science test_name do |e|
              e.before_run { cache.fetch_by_id(id) { control } }
              e.context({ domain: domain, accessor: accessor, method_name: method_name })
              e.use { control }
              e.try { cache.fetch_by_id(id) { nil } }
              e.clean do |value|
                if value.is_a?(GH::Domain::Cache::Cachable)
                  "#{value.class.name}##{value.id}"
                else
                  value
                end
              end
            end
            control
          end
        end
      end
    end
  end
end
