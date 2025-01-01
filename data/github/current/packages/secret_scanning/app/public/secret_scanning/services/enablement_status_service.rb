# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class EnablementStatusService
      include SecretScanning::Constants

      # Returns whether secret scanning is enabled for all repositories for the given organization
      #
      # @param org [Organization] the organization to check
      # @return [Array] array containing [enabled_boolean, error_or_nil]
      sig { params(org: Organization).returns([T::Boolean, T.nilable(StandardError)]) }
      def self.secret_scanning_enabled(org)
        req = GitHub::Proto::SecretScanning::Api::V1::GetEnablementStatusForOrgRequest.new(org_id: org.id)
        response = GitHub::TokenScanning::Service::Client.new(nil).get_enablement_status_for_org(req)

        # Use generic response processor. Treat missing data as invalid.
        is_data_valid = !!response&.data && response.data.respond_to?(:secret_scanning_enabled_on_all_repos)
        errored, err = ServiceHelper.process_response(
          response: response,
          operation: "checking secret scanning enablement status",
          is_data_valid: is_data_valid,
          is_404_ok: false,
          failbot_attributes: { "organization.id": org.id },
        )

        return false, err if errored && err
        return false, nil if errored || response.nil? # unreachable here unless err nil (e.g. allowed 404), but keep symmetry

        data = response.data
        return false, SecretScanning::Errors::ServiceError.new("Missing enablement status data") if data.nil?
        [data.secret_scanning_enabled_on_all_repos, nil]
      end
    end
  end
end
