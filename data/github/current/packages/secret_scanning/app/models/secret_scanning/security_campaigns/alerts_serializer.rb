
# typed: strict
# frozen_string_literal: true

module SecretScanning
  module SecurityCampaigns
    class AlertsSerializer
      extend SecretScanning::Features::FeatureFlagHelper
      include ScanningHelper

      FILE_PATH_TRUNCATION_LENGTH = 24

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
        serializer = new
        alerts.map do |alert|
          serializer.serialize_alert(alert)
        end
      end

      sig { params(alert: GitHub::TokenScanning::Service::Token).returns(T::Hash[Symbol, T.untyped]) }
      def serialize_alert(alert)
        is_fixed = alert.revoked?
        is_dismissed = alert.resolved? && !alert.revoked?
        resolved_timestamp = alert.resolved_at&.utc&.xmlschema

        hash = {
          alertType: "secret_scanning",
          number: alert.number,
          title: alert.label,
          ruleSeverity: "none", # Secret scanning doesn't use rule severity like code scanning
          securitySeverity: nil, # Secret scanning doesn't use security severity levels
          toolName: "Secret Protection",
          truncatedPath: alert.first_location&.path ? reverse_truncate_path(alert.first_location.path, FILE_PATH_TRUNCATION_LENGTH) : "",
          startLine: alert.first_location&.start_line || 0,
          createdAt: alert.created_at&.to_time&.utc&.xmlschema,
          isFixed: is_fixed,
          isDismissed: is_dismissed,
          fixedAt: is_fixed ? resolved_timestamp : nil,
          dismissedAt: is_dismissed ? resolved_timestamp : nil,
          resolution: alert.resolution&.upcase,
          repository: self.class.serialized_repository(repository: alert.repository),
          publiclyLeaked: alert.publicly_leaked,
          multiRepo: alert.multi_repo,
          validityActive: alert.validity_active?,
          rawSecret: alert.raw_secret,
        }

        # Add assignee if user is assigned
        assigned_user = alert.assigned_user
        if assigned_user.present?
          hash[:assignees] = [SecretScanning::Models::AssignedUser.from_user(assigned_user).serialize_ui]
        end

        hash
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
