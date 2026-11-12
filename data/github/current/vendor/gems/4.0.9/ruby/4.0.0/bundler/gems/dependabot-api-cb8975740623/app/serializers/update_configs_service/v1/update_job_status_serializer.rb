# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class UpdateJobStatusSerializer < ActiveModel::Serializer
      attributes :id,
                 :state,
                 :finished_at,
                 :errors,
                 :last_error,
                 :warnings,
                 :update_config_id,
                 :actions_external_id,
                 :runner_type,
                 :package_ecosystem,
                 :actions_workflow_run_id

      def state
        # Abandoned is an internal state functionally equivolent to cancelled
        # for external services
        return "CANCELLED" if object.current_state == "abandoned"

        object.current_state.to_s.upcase
      end

      def finished_at
        return unless object.completed?

        Google::Protobuf::Timestamp.new(
          seconds: object.last_transition.created_at.utc.to_i
        )
      end

      def errors
        object.unique_errors.map { |error| error_serializer.new(error).to_h }
      end

      def warnings
        object.update_job_warnings.map { |warning| warning_serializer.new(warning).to_h }
      end

      def last_error
        return unless object.update_job_errors.any?

        error_serializer.new(object.update_job_errors.last).to_h
      end

      def package_ecosystem
        package_ecosystem_serializer.new(object.update_config.package_manager, scope).to_h
      end

      private

      def error_serializer
        UpdateConfigsService::V1::UpdateJobErrorSerializer
      end

      def warning_serializer
        UpdateConfigsService::V1::UpdateJobWarningSerializer
      end

      def package_ecosystem_serializer
        UpdateConfigsService::V1::PackageEcosystemSerializer
      end
    end
  end
end
