# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordEcosystemMeta < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams, "data" => { type: Array, required: true }

      requires :update_job

      def call
        return invalid_json_error unless valid_ecosystem_data?

        ecosystem_data.each do |ecosystem|
          increment_metric(ecosystem[:ecosystem])
        end

        Renderer.no_content
      end

      private

      def ecosystem_data
        params.fetch(:data)
      end

      def valid_ecosystem_data?
        return false if ecosystem_data.empty?

        ecosystem_data.all? do |ecosystem|
          valid_ecosystem?(ecosystem[:ecosystem])
        end
      end

      def valid_ecosystem?(ecosystem)
        return false if ecosystem.nil?

        ecosystem[:name] &&
          valid_package_manager?(ecosystem[:package_manager]) &&
          valid_language_data?(ecosystem[:language])
      end

      def valid_package_manager?(package_manager)
        return false if package_manager.nil?

        package_manager[:name] &&
          package_manager[:version] &&
          package_manager[:raw_version]
      end

      def valid_language_data?(language)
        return true if language.nil?

        language[:name] &&
          language[:version] &&
          language[:raw_version]
      end

      def tags(ecosystem)
        result = { "ecosystem.name" => ecosystem[:name] }

        package_manager = ecosystem[:package_manager]
        package_requirement = package_manager.delete(:requirement)

        package_manager.each do |key, value|
          result["pkg_manager.#{key}"] = value
        end

        package_requirement&.each do |key, value|
          result["pkg_manager.requirement.#{key}"] = value
        end

        language = ecosystem[:language]

        unless language.nil?
          language_requirement = language.delete(:requirement)

          language.each do |key, value|
            result["language.#{key}"] = value
          end

          language_requirement&.each do |key, value|
            result["language.requirement.#{key}"] = value
          end
        end

        result
      end

      def increment_metric(ecosystem)
        update_job.increment_metric("update_job.ecosystem_meta", 1, tags: tags(ecosystem))
      end

      def invalid_json_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Invalid ecosystem data",
        )
      end
    end
  end
end
