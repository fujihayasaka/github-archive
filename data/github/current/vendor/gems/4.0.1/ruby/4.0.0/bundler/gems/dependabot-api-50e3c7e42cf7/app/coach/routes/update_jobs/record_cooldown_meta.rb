# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordCooldownMeta < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams, "data" => { type: Array, required: true }

      requires :update_job

      def call
        return invalid_json_error unless valid_cooldown_data?

        cooldown_data.each do |cooldown|
          increment_metric(cooldown[:cooldown])
        end

        Renderer.no_content
      end

      private

      def cooldown_data
        params.fetch(:data)
      end

      def valid_cooldown_data?
        return false if cooldown_data.empty?

        cooldown_data.all? do |cooldown|
          valid_cooldown?(cooldown[:cooldown])
        end
      end

      def valid_cooldown?(cooldown)
        return false if cooldown.nil?

        cooldown[:ecosystem_name] && cooldown[:config] && valid_config_data?(cooldown[:config])
      end

      def tags(cooldown)
        result = { "cooldown.ecosystem_name" => cooldown[:ecosystem_name] }

        cooldown_data = cooldown[:config]

        cooldown_data.each do |key, value|
          result["config.#{key}"] = value
        end

        result
      end

      def valid_config_data?(config)
        return false unless config

        config[:default_days] &&
          config[:semver_major_days] &&
          config[:semver_minor_days] &&
          config[:semver_patch_days]
      end

      def increment_metric(cooldown)
        update_job.increment_metric("update_job.cooldown_meta", 1, tags: tags(cooldown))
      end

      def invalid_json_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Invalid cooldown data",
        )
      end
    end
  end
end
