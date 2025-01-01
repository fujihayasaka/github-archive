# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class DatadogMetricCrumb < IndexCrumb
      def label
        "Datadog Metric Generator"
      end

      def path_name
        :devtools_datadog_metric_path
      end
    end
  end
end
