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
      attributes["gh.db.cluster.name"] = connection_class.respond_to?(:cluster_name) ? connection_class.cluster_name.to_s : GitHub::TaggingHelper::UNKNOWN
      attributes
    end
  end
end
