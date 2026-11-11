# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroAssessmentResultJob < Repositories::RepositoryHydroMessageJob
    queue_as :hydro_security_products_enablement_code_security_risk_assessment_result

    retry_on_dirty_exit

    sig { void }
    def perform
      assessment_id = T.let(message[:assessment_id], Integer)
      failure_reason = T.let(message.dig(:failure_reason, :value), T.nilable(String))
      raw_rules = T.let(message[:rules], T::Array[T::Hash[Symbol, T.untyped]])

      rules = raw_rules.map do |rule|
        {
          rule_id: rule[:id],
          rule_name: rule[:name],
          language: rule[:language],
          severity: rule[:severity].to_s.delete_prefix("SEVERITY_").downcase,
          autofix_supported: rule[:autofix_supported],
          vulnerability_count: rule[:vulnerability_count],
        }
      end

      with_write do
        CodeScanningAssessmentRepository.apply_csra_results!(
          assessment_id: assessment_id,
          repository_id: repository_id,
          rules: rules,
          failure_reason: failure_reason.presence,
        )
      end
    end
  end
end
