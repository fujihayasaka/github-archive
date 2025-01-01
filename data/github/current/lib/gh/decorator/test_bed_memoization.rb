# typed: true
# frozen_string_literal: true

module GH
  module Decorator
    module TestBedMemoization
      extend GH::Decorator
      extend Scientist

      sig { override.params(decorable: GH::Decorator::Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        raise "TestBedMemoization can only be applied to GH::Domain::Base classes" unless decorable < GH::Domain::Base

        domain = GitHub.packageowners.package_for_type(decorable)
        accessor = T.cast(decorable, T.class_of(GH::Domain::Base)).accessor_name
        # domain_caching_repositories_repositories_by_id
        test_name = "domain_caching_#{domain&.gsub("packages/", "")}_#{accessor}_#{method_name}"
        flipper_name = test_name.to_sym

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          next super(*args, **kwargs, &block) unless GH::Context.enabled? && GitHub.domain_interface_caching?

          cache = T.cast(self, GH::Domain::Base).cache

          feature_enabled = GH.identity_context.domain_actor&.feature_enabled?(flipper_name)
          feature_enabled = GitHub.flipper[flipper_name].enabled? if feature_enabled.nil?

          if feature_enabled
            cache.fetch(method_name, *args, **kwargs.merge({ method_name: })) do
              super(*args, **kwargs, &block)
            end
          else
            control = super(*args, **kwargs, &block)
            science test_name do |e|
              e.before_run { cache.fetch(method_name, *args, **kwargs.merge({ method_name: })) { control } }
              e.context({ domain: domain, accessor: accessor, method_name: method_name })
              e.use { control }
              e.try { cache.fetch(method_name, *args, **kwargs.merge({ method_name: })) { nil } }
              e.compare do |control, candidate|
                if control.is_a?(GH::Domain::Collection) && candidate.is_a?(GH::Domain::Collection)
                  next true if control.empty? && candidate.empty?
                  next control.to_a == candidate.to_a if control.first.is_a?(GH::Domain::Cache::Cachable)
                end
                control == candidate
              end
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
