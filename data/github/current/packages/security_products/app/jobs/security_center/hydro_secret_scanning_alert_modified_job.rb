# typed: strict
# frozen_string_literal: true

module SecurityCenter
  # This job subscribes to the InsightsEntityBatch topic, and receives a batch of modified alerts.
  # The naming here is confusing - it claims to be for "Alert" (singular), but does
  # in fact receive a batch of "Alerts" (plural). We had a bug where the class/queue names did not
  # match convention, and renaming a class is safe for in-flight jobs, where renaming a queue isn't.
  class HydroSecretScanningAlertModifiedJob < InsightsEntityBatchHydroMessageJob
    queue_as :hydro_security_center_secret_scanning_alert_modified

    sig { void }
    def perform
      return if repositories_to_process.blank?

      repositories_to_process.each do |repository|
        repository.security_center_notify(
          feature_type,
          source_event:,
          skip_subfeature_updates: true,
        )
      end

      instrument_repository_updated
    end

    private

    sig { override.returns(String) }
    def feature_type
      SecurityFeatures::SECRET_SCANNING
    end

    sig { override.returns(String) }
    def target_entity_type
      "secret_scanning_alert"
    end

    sig { override.returns(String) }
    def source_event
      "#{schema}.#{target_entity_type}"
    end
  end
end
