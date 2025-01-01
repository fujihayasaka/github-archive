# typed: true
# frozen_string_literal: true

module SecretScanning::PushProtection
  # View component detected secrets on web editor experience
  class FileUploadDetectedSecretsComponent < ApplicationComponent
    extend T::Sig

    sig { params(repository: Repository, secrets: T.nilable(T::Array[SecretScanning::Models::Secret]), upload_directory: T.nilable(String), base_branch: T.nilable(String), limited_user_bypass_experience_only: T::Boolean).void }
    def initialize(repository, secrets, upload_directory, base_branch, limited_user_bypass_experience_only = false)
      @repository = repository
      # The web experience only shows one secret at a time
      @secret = secrets[0] unless secrets.blank?
      @limited_user_bypass_experience_only = limited_user_bypass_experience_only
      @upload_directory = upload_directory
      @base_branch = base_branch
    end

    attr_reader :secret, :limited_user_bypass_experience_only

    sig { returns(T::Boolean) }
    def is_custom_pattern?
      @secret.is_custom_pattern?
    end

    sig { returns(T::Boolean) }
    def repo_has_secret_scanning_experience?
      SecretScanning::Features::Repo::TokenScanning.new(@repository).enabled?
    end

    sig { returns(String) }
    def token_type_label
      @secret.token_metadata&.label
    end

    sig { returns(String) }
    def file_name
      @secret.locations.first.path
    end

    sig { returns(T.nilable(SecretScanning::Models::PushProtection::CustomMessage)) }
    memoize def push_protection_custom_msg
      SecretScanning::Services::PushProtectionService.get_custom_message(@repository)
    end

    sig { returns(String) }
    def push_protection_url
      if limited_user_bypass_experience_only
        DocsUrlConfig.url_for("code-security/push-protection-for-users")
      else
        DocsUrlConfig.url_for("code-security/working-with-push-protection-in-the-github-ui-resolving-a-blocked-commit")
      end
    end
  end
end
