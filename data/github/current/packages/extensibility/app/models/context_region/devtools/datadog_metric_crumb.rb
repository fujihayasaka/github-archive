# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class DatadogMetricCrumb < IndexCrumb
      sig { override.returns(String) }
      def label
        "Datadog Metric Generator"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_datadog_metric_path
      end
    end
  end
end
