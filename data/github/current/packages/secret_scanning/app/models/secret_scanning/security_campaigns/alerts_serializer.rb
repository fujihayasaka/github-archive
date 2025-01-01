
# typed: strict
# frozen_string_literal: true

module SecretScanning
  module SecurityCampaigns
    class AlertsSerializer
      ## Serializes secret scanning alerts for the security campaigns UI.
      # This aligns with the types in ui/packages/security-campaigns/types/security-campaign-alert.ts
      sig do
        params(
          alerts: T::Array[GitHub::TokenScanning::Service::Token]
        ).returns(
          T::Array[T::Hash[Symbol, T.untyped]]
        )
      end
      def self.serialized_alerts(alerts:)
        alerts.map do |alert|
          {
            alertType: "secret_scanning",
            number: alert.number,
            title: alert.label,
            createdAt: alert.created_at&.to_time&.utc&.xmlschema,
            resolution: alert.resolution,
            repository: serialized_repository(repository: alert.repository),
            # TODO(robertbolender): isFixed/isDismissed/fixedAt/dismissedAt/assignees
          }
        end
      end

      sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
      def self.serialized_repository(repository:)
        {
          ownerLogin: repository.owner_display_login,
          name: repository.name,
          typeIcon: repository.repo_type_icon,
          defaultBranch: repository.default_branch,
        }
      end
    end
  end
end
