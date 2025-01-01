# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    class Type < T::Enum

      enums do
        DependabotAlerts = new("dependabot_alerts")
        FeatureEnablement = new("feature_enablement")
        CodeScanningAlert = new("code_scanning_alert")
        SecretScanningAlert = new("secret_scanning_alert")
        RepositoryMetadata = new("repository_metadata")

        Organizations = new("organizations")
        Users = new("users")

        Unknown = new("unknown")
      end

      sig { returns(T::Array[Type]) }
      def self.all
        self.values - [Type::Unknown]
      end
    end
  end
end
