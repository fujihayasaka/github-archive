# typed: true
# frozen_string_literal: true

module SecretScanning::PushProtection
  # View component detected secrets on web editor experience
  class WebEditorDetectedSecretsComponent < ApplicationComponent
    sig { params(repository: Repository, secrets: T.nilable(T::Array[SecretScanning::Models::Secret]), unblock_secret_success: T.nilable(T::Boolean)).void }
    def initialize(repository, secrets, unblock_secret_success)
      @repository = repository
      @unblock_secret_success = unblock_secret_success
      # The web experience only shows one secret at a time
      @secret = secrets[0] unless secrets.blank?
    end

    private

    attr_reader :unblock_secret_success, :secret

    sig { returns(T::Boolean) }
    def is_custom_pattern?
      @secret.is_custom_pattern?
    end

    sig { returns(String) }
    def token_type_label
      @secret.token_metadata&.label
    end

    sig { returns(Integer) }
    def start_line
      return 0 if @secret.locations.blank?
      @secret.locations[0].start_line
    end

    sig { returns(T.nilable(SecretScanning::Models::PushProtection::CustomMessage)) }
    memoize def push_protection_custom_msg
      SecretScanning::Services::PushProtectionService.get_custom_message(@repository)
    end
  end
end
