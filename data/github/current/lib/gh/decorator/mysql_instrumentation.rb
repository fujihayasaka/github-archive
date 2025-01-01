# typed: strict
# frozen_string_literal: true

module GH
  module Decorator
    module MysqlInstrumentation
      extend GH::Decorator

      sig { override.params(decorable: Decorable, method_name: Symbol).void }
      def self.decorate_method(decorable, method_name)
        domain = GitHub.packageowners.package_for_type(decorable)
        accessor = T.cast(decorable, T.class_of(GH::Domain::Base)).accessor_name

        decorate(decorable, method_name) do |*args, **kwargs, &block|
          tags = [
            "domain:#{domain}",
            "accessor:#{accessor}",
            "method:#{method_name}",
          ]

          before_cache_hits = GitHub::MysqlInstrumenter.cached_query_count
          before_query_count = GitHub::MysqlInstrumenter.query_count

          result = super(*args, **kwargs, &block)

          after_cache_hits = GitHub::MysqlInstrumenter.cached_query_count
          after_query_count = GitHub::MysqlInstrumenter.query_count

          GitHub.dogstats.count("domain.call.sql_cache_hits", after_cache_hits - before_cache_hits, tags:)
          GitHub.dogstats.count("domain.call.sql_query_count", after_query_count - before_query_count, tags:)

          result
        end
      end
    end
  end
end
