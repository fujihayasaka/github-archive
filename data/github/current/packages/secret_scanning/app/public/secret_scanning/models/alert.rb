# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class Alert < T::Struct
      prop :first_location_description, T.nilable(String)

      const :repository_id, Integer
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
      const :publicly_leaked, T.nilable(T::Boolean)
      const :multi_repo, T.nilable(T::Boolean)
      const :token_groups, T::Array[Validity::TokenGroup]
      const :validity, T.any(Symbol, Integer)
      const :validity_last_checked, T.nilable(Time)
      const :async_check_requested_at, T.nilable(Time)
      const :async_check_in_progress, T::Boolean
      const :is_multipart, T::Boolean
      const :slug, String
      const :is_classic_or_fine_grained_pat, T::Boolean
      const :first_location_in_actions_file, T::Boolean
      const :is_reported, T::Boolean
      const :is_base64_encoded, T.nilable(T::Boolean)
      const :decoded_base64_raw_secret, T.nilable(String)

      prop :feature_flags, T::Hash[Symbol, T::Boolean], default: {}
    end
  end
end
