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

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          next super(*args, **kwargs, &block) unless GH::Context.enabled?

          cache = T.cast(self, GH::Domain::Base).cache


          if GitHub.flipper[test_name.to_sym].enabled?
            cache.fetch_by_id(args.first) do
              super(*args, **kwargs, &block)
            end
          else
            control = super(*args, **kwargs, &block)
            science test_name do |e|
              e.context({ domain: domain, accessor: accessor, method_name: method_name })
              e.use { control }
              e.try { cache.fetch_by_id(args.first) { control } }
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
