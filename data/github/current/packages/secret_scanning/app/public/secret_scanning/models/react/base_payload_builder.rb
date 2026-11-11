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

        sig do
          params(
            alert: GitHub::TokenScanning::Service::Token,
            # with_* params optimize for not fetching extra data when serializing alert lists to prevent N+1 queries
            with_metadata: T::Boolean,
          ).returns(SecretScanning::Models::Alert)
        end
        def serialize_alert(alert, with_metadata: false)
          set_raw_secret_from_encrypted_secret(alert)

          if alert.raw_secret.nil?
            SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert)
          end

          created_at = alert.first_location ? alert.first_location.created_at : alert.created_at
          validation_support = get_validation_support(alert)

          assigned_user = SecretScanning::Models::AssignedUser.from_token(alert)

          partner_metadata = SecretScanning::Features::Repo::PartnerMetadata.new(@repo)
          metadata_for_token_type_explicitly_disabled = partner_metadata.metadata_for_token_type_explictly_disabled?(alert.token_type)
          partner_metadata_supported = partner_metadata.feature_available? &&
            (alert.metadata_supported || false) &&
            !metadata_for_token_type_explicitly_disabled

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
            validity_manually_set: alert.validity_manually_set?,
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
            partner_metadata_supported: partner_metadata_supported,
            secret_metadata: if feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::INCLUDE_STORED_METADATA) && with_metadata
                               SecretScanning::Models::PartnerTokenMetadata.build_from_token(alert, repo: @repo, user: @user)
                             end,
            metadata: if feature_flag_enabled_in_hierarchy?(@repo, FeatureFlags::INCLUDE_STORED_METADATA)
                        SecretScanning::Models::PartnerTokenMetadata.decrypt_to_pairs(alert.encrypted_metadata)
                      end,
          )
        end

        sig { params(user: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
        def serialize_displayed_user(user)
          SecretScanning::Models::React::BasePayloadBuilder.serialize_displayed_user(user)
        end

        # TODO: This should live somewhere else if it's gonna be static and called by others.
        sig { params(user: T.nilable(User)).returns(T::Hash[Symbol, T.untyped]) }
        def self.serialize_displayed_user(user)
          u = user || User.ghost
          {
            avatar_url: u.primary_avatar_url,
            display_login: u.display_login,
          }
        end

        # Deprecated: Migrating away to stored metadata.
        # Kept for old non-stored metadata.
        sig { params(token_metadata: SecretScanning::Models::GitHubTokenMetadata, token_owner: T.nilable(User)).returns(T.nilable(String)) }
        def get_token_link(token_metadata, token_owner)
          return nil if token_metadata.link.nil?

          if @user.id == token_owner&.id
            return token_metadata.link
          end

          if token_metadata.token_type == "GITHUB_TOKEN_V2"
            return nil unless token_metadata.link.include?("organizations")
            repo_owner = @repo.owner
            token_metadata.link if repo_owner.is_a?(::Organization) && SecurityProduct::Permissions::OrgAuthz.new(repo_owner, actor: @user).can_manage_org_security_products?
          end
        end

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
