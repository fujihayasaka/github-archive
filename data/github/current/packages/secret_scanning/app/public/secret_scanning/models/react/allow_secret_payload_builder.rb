# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module React
      class AllowSecretPayloadBuilder < BasePayloadBuilder

        sig do
          params(
            bypass_placeholder: SecretScanning::Models::BypassPlaceholder,
            limited_user_bypass_experience_only: T::Boolean).returns(T.nilable(T::Hash[T.untyped, T.untyped]))
        end
        def page_payload(bypass_placeholder:, limited_user_bypass_experience_only:)
          {
            owner_display_login: @repo.owner_display_login,
            repo_name: @repo.name,
            bypass_metadata: {
              token_label: bypass_placeholder.token_metadata.label,
              owner_display_login: @repo.owner_display_login,
              repo_name: @repo.name,
              placeholder_ksuid: bypass_placeholder.ksuid,
              is_custom_pattern: bypass_placeholder.token_metadata.is_custom_pattern?,
              limited_user_bypass_experience_only: limited_user_bypass_experience_only,
              push_protection_custom_message: push_protection_custom_message,
              repo_has_secret_scanning_experience: SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?,
              use_delegated_bypass_flow: SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@repo, @user),
            },
            help_url: GitHub.help_url,
          }
        end

        sig do
          params(
            token_metadata_label: String,
            bypass_placeholder_ksuid: String,
            is_custom_pattern: T::Boolean,
            limited_user_bypass_experience_only: T::Boolean,
            first_secret_location: T::Hash[Symbol, Numeric],
            rule_suite_id: T.nilable(Integer),
          ).returns(T.nilable(T::Hash[T.untyped, T.untyped]))
        end
        def blob_edit_bypass_metadata(
          token_metadata_label:,
          bypass_placeholder_ksuid:,
          is_custom_pattern:,
          limited_user_bypass_experience_only:,
          first_secret_location:,
          rule_suite_id: 0)
          {
            token_label: token_metadata_label,
            owner_display_login: @repo.owner_display_login,
            repo_name: @repo.name,
            placeholder_ksuid: bypass_placeholder_ksuid,
            is_custom_pattern: is_custom_pattern,
            limited_user_bypass_experience_only: limited_user_bypass_experience_only,
            push_protection_custom_message: push_protection_custom_message,
            repo_has_secret_scanning_experience: SecretScanning::Features::Repo::TokenScanning.new(@repo).enabled?,
            first_secret_location: first_secret_location,
            use_delegated_bypass_flow: SecretScanning::Services::DelegatedBypassService.use_delegated_bypass_flow(@repo, @user),
            rule_suite_id: rule_suite_id,
          }
        end

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def push_protection_custom_message
          custom_msg = SecretScanning::Services::PushProtectionService.get_custom_message(@repo)
          if custom_msg.present?
            {
              message: custom_msg.message,
              owner_name: custom_msg.owner_name,
              owner_type: custom_msg.owner_type,
            }
          end
        end
      end
    end
  end
end
