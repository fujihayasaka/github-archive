# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class IncrementMetric < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::ReadReplica
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.metric" => { type: String, required: true },
           "data.tags" => { type: Hash, required: true }

      requires :update_job

      PERMITTED_METRICS_AND_TAGS = {
        "updater.started" => [:operation],
      }.freeze

      PERMITTED_TAG_LENGTH = 32

      def call
        increment_metric if metric_permitted?
        Renderer.no_content
      end

      private

      def increment_metric
        update_job.increment_metric(metric_name, tags: filtered_tags)
      end

      def metric_name
        params.fetch(:data).fetch(:metric)
      end

      def metric_permitted?
        PERMITTED_METRICS_AND_TAGS.key?(metric_name)
      end

      def tags
        params.fetch(:data).fetch(:tags)
      end

      def filtered_tags
        PERMITTED_METRICS_AND_TAGS[metric_name].index_with do |tag_name|
          truncate(tags.fetch(tag_name, nil))
        end
      end

      def truncate(tag_value)
        return tag_value if tag_value.length <= PERMITTED_TAG_LENGTH

        "#{tag_value[0...(PERMITTED_TAG_LENGTH - 3)]}..."
      end
    end
  end
end
