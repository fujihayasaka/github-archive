# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class Alert < T::Struct
      extend T::Sig

      prop :first_location_description, T.nilable(String)

      const :number, Integer
      const :label, String
      const :token_type, String
      const :raw_secret, T.nilable(String)
      const :resolution, T.nilable(String)
      const :created_at, Time
      const :resolved_at, T.nilable(Time)
      const :is_closed, T::Boolean
      const :token_type_provider, String
      const :partner_remediation_url, T.nilable(String)
      const :validation_support, ValidationSupport
      const :low_confidence, T::Boolean
      const :llm_detected, T::Boolean
      const :token_groups, T::Array[Validity::TokenGroup]
      const :validity, T.any(Symbol, Integer)
      const :validity_last_checked, T.nilable(Time)
      const :async_check_requested_at, T.nilable(Time)
      const :async_check_in_progress, T::Boolean
      const :is_multipart, T::Boolean
      const :slug, String
    end
  end
end
