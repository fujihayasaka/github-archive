# typed: strict
# frozen_string_literal: true

module GH
  module Decorator

    # This decorator _requires_ the decorable to be a GH::Domain::Base. It reports to DataDog the domain's caller service,
    # package, and accessor via the "domain.call" distribution metric.
    module CallerAttribution
      extend GH::Decorator

      sig { override.params(decorable: Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        domain = GitHub.packageowners.package_for_type(decorable)
        accessor = T.cast(decorable, T.class_of(GH::Domain::Base)).accessor_name

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          catalog_service = GitHub.context[:catalog_service].to_s.underscore.presence || "unknown"
          tags = [
            "calling_catalog_service:#{catalog_service}",
            "domain:#{domain}",
            "accessor:#{accessor}",
            "method:#{method_name}",
          ]
          GitHub.dogstats.distribution_time("domain.call", tags: tags) do
            super(*args, **kwargs, &block)
          end
        end
      end
    end
  end
end
