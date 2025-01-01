# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class HydroCodeScanningAlertsModifiedJob < InsightsEntityBatchHydroMessageJob
    queue_as :hydro_security_center_code_scanning_alerts_modified

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
      SecurityFeatures::CODE_SCANNING
    end

    sig { override.returns(String) }
    def target_entity_type
      "code_scanning_alert"
    end

    sig { override.returns(String) }
    def source_event
      "#{schema}.#{target_entity_type}"
    end
  end
end
