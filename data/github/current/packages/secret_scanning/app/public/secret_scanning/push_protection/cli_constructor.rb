# typed: strict
# frozen_string_literal: true

module SecretScanning
  module PushProtection
    class CliConstructor
      extend T::Sig
      include SecurityAnalysisSettingsHelper
      include SecretScanning::Features::FeatureFlagHelper
      include SecretScanning::Constants
      include SecretScanning::BypassDelegation

      OWNER_TYPE_ORG = "organization"
      OWNER_TYPE_ENTERPRISE = "enterprise"

      sig { params(repository: Repository, actor: T.any(User, PublicKey), use_delegated_bypass_flow: T::Boolean).void }
      def initialize(repository, actor, use_delegated_bypass_flow)
        @repository = repository
        @actor = T.let(actor, T.any(User, PublicKey))
        @use_delegated_bypass_flow = use_delegated_bypass_flow
      end

      sig { returns(String) }
      def self.get_short_message
        "Push cannot contain secrets"
      end

      # Build and return the long message for a blocked push
      # Note: everything below is pre-formatted, do not change indentation as it will change the CLI output alignment
      sig { params(scan_result: SecretScanning::Models::SynchronousScanResult, secret_bypass_placeholder_ksuids_to_urls: T::Hash[String, String]).returns(String) }
      def get_long_message(scan_result, secret_bypass_placeholder_ksuids_to_urls)
        secrets_msg = ""

        scan_result.secrets.each_with_index do |secret, i|
          type_label = secret.token_metadata.label

          secrets_msg += <<-SECRETMSG
  —— #{type_label} #{'—' * [(50 - type_label.length), 0].max}
      SECRETMSG

          unless secret.locations.blank?
            secrets_msg += <<-SECRETMSG
   locations:
     SECRETMSG
            secrets_msg += get_location_msg(secret.locations, scan_result.completed)
          end

          action = "allow the secret"
          if @use_delegated_bypass_flow
            action = "request an exemption"
          end

          secrets_msg += <<-SECRETMSG

   (?) To push, remove secret from commit(s) or follow this URL to #{action}.
   #{secret_bypass_placeholder_ksuids_to_urls[T.must(secret.bypass_placeholder_ksuid)]}
SECRETMSG
          # Only add a separator if this isn't the last secret. When the CLI message is
          # outputted as part of RuleSuite.additional_cli_msg, there already is padding at the end, so not including
          # this check results in extra long whitespace at the end of the message.
          if i < scan_result.secrets.length - 1
            secrets_msg += "\n\n"
          end
        end

        enable_secret_scanning_msg = ""
        if !SecretScanning::Features::Repo::TokenScanning.new(@repository).enabled? && can_manage_settings?
          enable_secret_scanning_msg = <<-ENABLEMSG
 (?) This repository does not have Secret Scanning enabled, but is eligible. Enable Secret Scanning to view and manage detected secrets.
 Visit the repository settings page, #{GitHub.url}#{security_analysis_settings_path(@repository)}

          ENABLEMSG
        end

        long_message = <<-LONGMESSAGE
#{get_custom_msg}
 (?) Learn how to resolve a blocked push
 #{DocsUrlConfig.url_for("code-security/working-with-push-protection-from-the-command-line-resolving-a-blocked-push")}

#{enable_secret_scanning_msg}
#{secrets_msg}
    LONGMESSAGE
        if !scan_result.completed || scan_result.num_secrets_found_over_limit > 0
          long_message += <<-LONGMESSAGE
      LONGMESSAGE

          if !scan_result.completed
            long_message += <<-LONGMESSAGE

——[ WARNING ]—————————————————————————————————————————
 Scan incomplete: This push was large and we didn't finish on time.
 It can still contain undetected secrets.

 (?) Use the following command to find the path of the detected secret(s):
     git rev-list --objects --all | grep blobid
——————————————————————————————————————————————————————
        LONGMESSAGE

          elsif scan_result.num_secrets_found_over_limit > 0
            long_message += <<-LONGMESSAGE

——[ WARNING ]—————————————————————————————————————————
 #{scan_result.num_secrets_found_over_limit} more secrets detected. Remove each secret from your commit history to view more detections.
 #{DocsUrlConfig.url_for("code-security/excluding-folders-and-files-from-secret-scanning")}
——————————————————————————————————————————————————————
        LONGMESSAGE
          end
        end

        long_message
      end

      private

      sig { returns(T::Boolean) }
      def can_manage_settings?
        return false unless @actor.is_a?(::User)
        SecurityProduct::Permissions::RepoAuthz.new(@repository, actor: @actor).can_manage_security_products?
      end

      sig { returns(T.nilable(String)) }
      def owner_type
        org = @repository.organization
        business = @repository.business
        if !org.nil? && SecretScanning::Features::Org::PushProtection.new(org).custom_message_active?
          return OWNER_TYPE_ORG
        end
        if !business.nil? && SecretScanning::Features::Business::PushProtection.new(business).custom_message_active?
          OWNER_TYPE_ENTERPRISE
        end
      end

      sig { returns(T.nilable(String)) }
      def owner_name
        org = @repository.organization
        org.name if org.present?
      end

      sig { params(locations: T::Array[SecretScanning::Models::Location], completed: T::Boolean).returns(String) }
      def get_location_msg(locations, completed)
        secrets_msg = ""
        if completed
          locations.each do |location|
            secrets_msg += <<-SECRETMSG
     - commit: #{location.commit_oid}
       path: #{location.path}:#{location.start_line}
        SECRETMSG
          end
        else
          locations.each do |location|
            secrets_msg += <<-SECRETMSG
     - blob id: #{location.blob_oid}
        SECRETMSG
          end
        end
        secrets_msg
      end

      sig { returns(T::Boolean) }
      def has_custom_msg?
        org = @repository.organization
        T.must(org.present? && SecretScanning::Features::Org::PushProtection.new(org).custom_message_active?)
      end

      sig { returns(String) }
      def get_custom_msg
        custom_msg = SecretScanning::Services::PushProtectionService.get_custom_message(@repository)
        return "" if custom_msg.nil?

        msg = <<-CUSTOMMSG

 (?) Review a resource from your #{custom_msg.owner_type}, #{custom_msg.owner_name}:
 #{custom_msg.message}
    CUSTOMMSG
        msg
      end
    end
  end
end
