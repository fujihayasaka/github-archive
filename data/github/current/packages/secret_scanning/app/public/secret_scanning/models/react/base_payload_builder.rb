# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class BasePayloadBuilder
        include SecretScanning::Encryption::EncryptedSecretsHelper
        include GitHub::TokenScanning::SecretScanningHelper
        include SecretScanning::Features::FeatureFlagHelper

        FILE_PATH_TRUNCATION_LENGTH = 24

        sig { params(repo: Repository, user: User).void }
        def initialize(repo, user)
          @repo = repo
          @user = user
        end

        sig { returns(T::Boolean) }
        def show_user_feedback_link?
          SecretScanning::Features::Repo::TokenScanning.new(@repo).feedback_link_enabled? &&
            !@user.dismissed_notice?(UserNotice::SECRET_SCANNING_FEEDBACK_NOTICE)
        end

        sig { params(alert: GitHub::TokenScanning::Service::Token).returns(SecretScanning::Models::Alert) }
        def serialize_alert(alert)
          set_raw_secret_from_encrypted_secret(alert)

          if alert.raw_secret.nil?
            SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert)
          end

          created_at = alert.first_location ? alert.first_location.created_at : alert.created_at
          validation_support = get_validation_support(alert)

          assigned_user = SecretScanning::Models::AssignedUser.from_token(alert)

          SecretScanning::Models::Alert.new(
            repository_id: alert.repository_id,
            number: alert.number,
            label: alert.label,
            token_type: alert.token_type,
            raw_secret: alert.raw_secret,
            resolution: alert.resolution,
            created_at: created_at,
            resolved_at: alert.resolved_at,
            is_closed: alert.resolved?,
            token_type_provider: alert.token_type_provider,
            partner_remediation_url: alert.external_remediation_doc_url,
            validation_support: validation_support,
            low_confidence: alert.low_confidence,
            llm_detected: alert.llm_detected,
            multi_repo: alert.multi_repo,
            publicly_leaked: alert.publicly_leaked,
            token_groups: alert.token_groups,
            validity: alert.validity,
            validity_last_checked: alert.validity_last_checked,
            async_check_requested_at: alert.async_check_requested_at,
            async_check_in_progress: alert.async_check_in_progress?,
            is_multipart: alert.is_multipart,
            slug: alert.token.slug,
            is_classic_or_fine_grained_pat: alert.is_classic_or_fine_grained_pat?,
            first_location_in_actions_file: alert.first_location_in_actions_file?,
            is_reported: alert.is_reported,
            is_base64_encoded: alert.is_base64_encoded,
            decoded_base64_raw_secret: alert.decoded_base64_raw_secret,
            assigned_users: assigned_user ? [assigned_user] : nil,
          )
        end

        sig { params(user: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_displayed_user(user)
          {
            avatar_url: user&.primary_avatar_url,
            display_login: user&.display_login,
          }
        end

        private

        sig { params(alert: GitHub::TokenScanning::Service::Token).returns(SecretScanning::Models::ValidationSupport) }
        def get_validation_support(alert)
          on_demand_checks_supported = alert.on_demand_checks_supported?
          validity_checks_supported = alert.validity_checks_supported?

          validation_support = SecretScanning::Models::ValidationSupport.new(
            on_demand_checks_supported: on_demand_checks_supported,
            validity_checks_supported: validity_checks_supported
          )

          validation_support
        end
      end
    end
  end
end
