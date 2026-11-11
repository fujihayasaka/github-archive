# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordMetrics < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::ReadReplica
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data" => { type: Array, required: true }

      requires :update_job

      METRIC_TYPE_VALUES = %w(increment distribution).freeze
      PERMITTED_METRICS_AND_TAGS = {
        # Add more permitted metrics as needed
        "updater.started" => [:operation],
        "dependabot.job_proxy.http_response_duration_ms" => %i(package_manager grouped_update request_host),
        "dependabot.job_proxy.http_response_count" => %i(package_manager grouped_update request_host response_code),
        "dependabot.job_proxy.http_request_count" => %i(package_manager grouped_update request_host),
        "update_job.ecosystem_meta" => %i(ecosystem_name package_manager_name package_manager_raw_version
                                          package_manager_version requirement_raw_constraint requirement_min_raw_version
                                          requirement_min_version requirement_max_raw_version requirement_max_version
                                          language_name language_raw_version language_version
                                          language_requirement_max_version language_requirement_raw_constraint
                                          language_requirement_min_raw_version language_requirement_min_version
                                          language_requirement_max_raw_version),
        "dependabot.action.ghcr_image_pull" => %i(package_manager org),
      }.freeze
      PERMITTED_TAG_LENGTH = 32

      def call
        return invalid_json_error unless valid_metrics_data?

        metrics_data.each do |metric|
          process_metric(metric)
        end

        Renderer.no_content
      end

      private

      def metrics_data
        params.fetch(:data)
      end

      def valid_metrics_data?
        metrics_data.all? do |metric|
          valid_metric?(metric)
        end
      end

      def valid_metric?(metric)
        metric.is_a?(Hash) &&
          PERMITTED_METRICS_AND_TAGS.key?(metric[:metric]) &&
          METRIC_TYPE_VALUES.include?(metric[:type]) &&
          valid_tags?(metric) &&
          valid_values?(metric) &&
          valid_increment_value?(metric)
      end

      def valid_tags?(metric)
        metric.fetch(:tags, {}).all? do |tag, value|
          (tag.is_a?(Symbol) || tag.is_a?(String)) && value.is_a?(String)
        end
      end

      def valid_values?(metric)
        return true unless metric[:type] == "distribution"

        metric.fetch(:values, []).all? { |value| value.is_a?(Numeric) }
      end

      def valid_increment_value?(metric)
        return true unless metric[:type] == "increment"

        metric.fetch(:value, 1).is_a?(Numeric) && metric[:value].positive?
      end

      def process_metric(metric)
        case metric[:type]
        when "increment"
          increment_metric(metric)
        when "distribution"
          record_distribution(metric)
        end
      end

      def increment_metric(metric)
        increment_value = metric.fetch(:value, 1)
        update_job.increment_metric(metric[:metric], increment_value, tags: filtered_tags(metric))
      end

      def record_distribution(metric)
        metric[:values].each do |value|
          update_job.distribution_metric(metric[:metric], value, tags: filtered_tags(metric))
        end
      end

      def invalid_json_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Invalid metrics data",
        )
      end

      def filtered_tags(metric)
        PERMITTED_METRICS_AND_TAGS[metric[:metric]].index_with do |tag_name|
          truncate(metric[:tags].fetch(tag_name, nil))
        end
      end

      def truncate(tag_value)
        return tag_value if tag_value && tag_value.length <= PERMITTED_TAG_LENGTH

        tag_value.to_s[0...(PERMITTED_TAG_LENGTH - 3)] + "..."
      end
    end
  end
end
