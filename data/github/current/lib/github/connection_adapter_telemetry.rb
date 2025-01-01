# typed: true
# frozen_string_literal: true

module GitHub
  module ConnectionAdapterTelemetry
    extend T::Helpers
    requires_ancestor { ActiveRecord::ConnectionAdapters::AbstractAdapter }

    def query(...)
      OpenTelemetry::Instrumentation::Trilogy.with_attributes(query_attributes) do
        super
      end
    end

    def raw_execute(...)
      OpenTelemetry::Instrumentation::Trilogy.with_attributes(query_attributes) do
        super
      end
    end

    private def query_attributes
      attributes = {}
      cluster_name = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name.to_s : GitHub::TaggingHelper::UNKNOWN
      attributes["gh.db.cluster.name"] = cluster_name

      if !GitHub::MysqlInstrumenter.within_graceful_degradation_wrapper
        if GitHub.respond_to?(:context) && GitHub.context[:required_clusters] && !GitHub.context[:required_clusters].include?(cluster_name.to_sym)
          attributes["gh.resilience.within_graceful_degradation_wrapper"] = false
        end
      end

      attributes
    end
  end
end
