# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class PushProtectionService
      extend T::Sig
      include SecretScanning::Constants

      # Scan duration limit in milliseconds.
      # Should be less than GitHub::TokenScanning::Service::Client::READ_TIMEOUT otherwise the extra scan time will be wasted
      SCAN_DURATION_LIMIT = 2700
      FOUND_SECRETS_LIMIT = 5

      BYPASS_ERROR = "PushProtectionServiceBypassError"

      OWNER_TYPE_ORG = "organization"
      OWNER_TYPE_ENTERPRISE = "enterprise"

      # Scan arbitrary contents for secrets
      # This method fails open - ie. failed and incomplete scans return the same as a successful scan with no results.
      sig do
        params(content: String,
               repository: Repository,
               actor: T.any(User, PublicKey),
               file_path: T.nilable(String),
               secrets_limit: Integer,
               delegated_bypass_enabled: T::Boolean,
              ).returns(SecretScanning::Models::SynchronousScanResult)
      end
      def self.scan_content(content, repository, actor, file_path = nil, secrets_limit = FOUND_SECRETS_LIMIT, delegated_bypass_enabled: false)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stats_tags = ["method:scan_content"]

        begin
          flag_builder = SecretScanning::Instrumentation::RepositoryServiceFlags.new(repository)
          push_protection = SecretScanning::Features::Repo::PushProtection.new(repository)
          delegated_bypass_requests = nil
          if delegated_bypass_enabled
            delegated_bypass_requests = DelegatedBypassService.get_delegated_bypass_requests(repository, actor)
          end

          request = {
            repository: {
              id: repository.id,
              default_branch: repository.default_branch,
            },
            content: content.b,
            path: file_path&.b,
            scan_duration: SecretScanning::Util::Protobuf::Duration.from_milliseconds(SCAN_DURATION_LIMIT),
            limit: secrets_limit,
            actor_id: actor.id,
            feature_flags: flag_builder.scans_api_service_flags,
            delegated_bypass_requests: delegated_bypass_requests,
          }

          if repository.owner&.organization?
            org = T.cast(repository.owner, Organization)
            org_hash = {
              owner: {
                id: org.id
              }
            }
            request[:repository].update(org_hash)

            if org.business.present?
              business = T.cast(org.business, Business)
              request[:business_id] = business.id
            end
          end

          response = GitHub::TokenScanning::Service::Client.new(actor).scan_bytes(request)

          if response.nil? || response.error || response.data.nil?
            stats_tags << "errored:true"
            stats_tags << "complete:false"
            return SecretScanning::Models::SynchronousScanResult.new
          end

          stats_tags << "errored:false"
          data = response.data

          if data.completed
            stats_tags << "complete:true"
          else
            stats_tags << "complete:false"
          end

          if data.secrets.length == 0
            stats_tags << "blocked:false"
          else
            stats_tags << "blocked:true"
          end

          GitHub.dogstats.distribution("secret_scanning.push_protection.scan_contents.num_secrets", data.secrets.length + data.num_secrets_found_over_limit, tags: stats_tags)

          found_secrets = data.secrets.map { |secret| from_proto_secret(secret) }

          SecretScanning::Models::SynchronousScanResult.new(
            secrets: found_secrets,
            completed: data.completed,
            num_secrets_found_over_limit: data.num_secrets_found_over_limit,
            used_delegated_bypass_request_ids: data.used_delegated_bypass_request_ids.to_a,
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e, app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: actor.id)
          GitHub.dogstats.increment("secret_scanning.push_protection.failure", tags: stats_tags)
          SecretScanning::Models::SynchronousScanResult.new(completed: false)
        ensure
          if start_time.present?
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            GitHub.dogstats.distribution("secret_scanning.push_protection.scan_content.time", (end_time - start_time) * 1000, tags: stats_tags)
          end
        end
      end

      # Scan a set of ref updates. Typically this will be a push.
      # This method fails open - ie. failed and incomplete scans return the same as a successful scan with no results.
      sig do
        params(ref_updates: T::Array[Git::Ref::Update],
               repository: Repository,
               actor: T.any(User, PublicKey),
               push_state: T.untyped,
               delegated_bypass_enabled: T::Boolean,
              ).returns(SecretScanning::Models::SynchronousScanResult)
      end
      def self.scan_ref_updates(ref_updates, repository, actor, push_state: nil, delegated_bypass_enabled: false)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stats_tags = ["method:scan_ref_updates"]

        begin
          ref_scopes = ref_updates.map do |ref_update|
            {
              name: ref_update.refname.b,
              before_oid: ref_update.before_oid,
              after_oid: ref_update.after_oid,
            }
          end

          flag_builder = SecretScanning::Instrumentation::RepositoryServiceFlags.new(repository)
          push_protection = SecretScanning::Features::Repo::PushProtection.new(repository)
          delegated_bypass_requests = nil
          if delegated_bypass_enabled
            delegated_bypass_requests = DelegatedBypassService.get_delegated_bypass_requests(repository, actor)
          end

          request = {
            repository: {
              id: repository.id,
              default_branch: repository.default_branch,
            },
            reference_updates: ref_scopes,
            scan_duration: SecretScanning::Util::Protobuf::Duration.from_milliseconds(SCAN_DURATION_LIMIT),
            limit: FOUND_SECRETS_LIMIT,
            actor_id: actor.id,
            push_state: push_state,
            feature_flags: flag_builder.scans_api_service_flags,
            delegated_bypass_requests: delegated_bypass_requests
          }

          if repository.owner&.organization?
            org = T.cast(repository.owner, Organization)
            org_hash = {
              owner: {
                id: org.id
              }
            }
            request[:repository].update(org_hash)

            if org.business.present?
              business = T.cast(org.business, Business)
              request[:business_id] = business.id
            end
          end

          response = GitHub::TokenScanning::Service::Client.new(actor).scan_push(request)

          if response.nil? || response.error || response.data.nil?
            stats_tags << "errored:true"
            stats_tags << "complete:false"
            return SecretScanning::Models::SynchronousScanResult.new(completed: false)
          end

          stats_tags << "errored:false"
          data = response.data

          if data.completed
            stats_tags << "complete:true"
          else
            stats_tags << "complete:false"
          end

          GitHub.dogstats.distribution("secret_scanning.push_protection.scan_ref_updates.num_secrets", data.secrets.length + data.num_secrets_found_over_limit, tags: stats_tags)

          # No secrets found
          if data.secrets.length == 0
            stats_tags << "blocked:false"

            return SecretScanning::Models::SynchronousScanResult.new(completed: data.completed, used_delegated_bypass_request_ids: data.used_delegated_bypass_request_ids.to_a)
          end

          # Secrets found
          stats_tags << "blocked:true"
          found_secrets = data.secrets.map { |secret| from_proto_secret(secret) }

          SecretScanning::Models::SynchronousScanResult.new(
            secrets: found_secrets,
            completed: data.completed,
            num_secrets_found_over_limit: data.num_secrets_found_over_limit,
            used_delegated_bypass_request_ids: data.used_delegated_bypass_request_ids.to_a
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e, app: FAILBOT_APP_NAME, repository_id: repository.id, user_id: actor.id)
          GitHub.dogstats.increment("secret_scanning.push_protection.failure", tags: stats_tags)
          SecretScanning::Models::SynchronousScanResult.new(completed: false)
        ensure
          if start_time.present?
            end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            GitHub.dogstats.distribution("secret_scanning.push_protection.scan_ref_updates.time", (end_time - start_time) * 1000, tags: stats_tags)
          end
        end
      end

      # Allows a secret to be (temporarily) pushed to a repository
      sig { params(token_type: String, token_signature: String, reason: String, repository: Repository, actor: User).returns(T::Boolean) }
      def self.allow_secret(token_type, token_signature, reason, repository, actor)
        request = {
          owner_id: repository.id,
          owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE,
          actor_id: actor.id,
          token_type: token_type,
          signature: token_signature,
          reason: SecretScanning::Models::BypassReason.to_proto_enum(reason)
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).add_bypass(request)

        if response.nil? || response.error
          return false
        end

        true
      end

      sig do
        params(reason: String,
               repository: Repository,
               actor: User,
               bypass_placeholder_ksuid: String).returns([T.nilable(SecretScanning::Models::Bypass), T.nilable(String)])
      end
      def self.promote_bypass(reason, repository, actor, bypass_placeholder_ksuid)
        request = {
          owner_id: repository.id,
          owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE,
          actor_id: actor.id,
          reason: SecretScanning::Models::BypassReason.to_proto_enum(reason),
          placeholder_ksuid: bypass_placeholder_ksuid
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).promote_bypass(request)

        return nil, response.error.msg if response&.error.present?

        data = response&.data&.bypass

        return nil, "An error has occurred while allowing the secret." if data.nil?

        [
          SecretScanning::Models::Bypass.from_proto(data),
          nil
        ]
      end

      sig { params(msg: T.nilable(String)).returns(T::Boolean) }
      def self.bypass_placeholder_not_found?(msg)
        return true if msg == "bypass placeholder not found"
        false
      end

      sig do
        params(repository: Repository,
               actor: T.any(User, String),
               bypass_placeholder_ksuid: String).returns([T.nilable(SecretScanning::Models::BypassPlaceholder), T.nilable(String)])
      end
      def self.get_bypass_placeholder(repository, actor, bypass_placeholder_ksuid)
        request = {
          owner_id: repository.id,
          owner_scope: GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE,
          placeholder_ksuid: bypass_placeholder_ksuid
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypass_placeholder(request)

        return nil, "An error has occurred while attempting to retrieve the bypass." if response.nil?
        return nil, response.error.msg if response.error.present?
        return nil, "Failed to retrieve bypass data." if response.data.nil?

        [self.from_proto_bypass_placeholder(response.data.placeholder), nil]
      end

      sig { params(repo: Repository).returns(T.nilable(SecretScanning::Models::PushProtection::CustomMessage)) }
      def self.get_custom_message(repo)
        org = repo.organization
        business = repo.business
        business ||= Business.enterprise_managed_business_for(resource: repo)
        business ||= GitHub.global_business if GitHub.single_business_environment?

        owner_name = nil
        owner_type = nil
        message = nil
        if !org.nil? && SecretScanning::Features::Org::PushProtection.new(org).custom_message_active?
          owner_name = org.name
          message = org.get_push_protection_custom_message
          owner_type = OWNER_TYPE_ORG
        elsif !business.nil? && SecretScanning::Features::Business::PushProtection.new(business).custom_message_active?
          owner_name = business.name
          message = business.get_push_protection_custom_message
          owner_type = OWNER_TYPE_ENTERPRISE
        end

        if owner_type.nil? || owner_name.nil? || message.nil?
          return nil
        end

        SecretScanning::Models::PushProtection::CustomMessage.new(owner_name:, owner_type:, message:)
      end

      # Creates a SecretScanning::Models::Secret from Github::Proto::SecretScanning::Scans::V2::Secret
      sig { params(secret: GitHub::Proto::SecretScanning::Scans::V2::Secret).returns(SecretScanning::Models::Secret) }
      def self.from_proto_secret(secret)
        metadata = secret.token_metadata
        token_metadata = if metadata != nil
          SecretScanning::Models::TokenMetadata.new(
          token_type: metadata.token_type,
          slug: metadata.slug,
          label: metadata.label,
          provider: metadata.provider,
        )
        else
          SecretScanning::Models::TokenMetadata.new(
            token_type: secret.type,
            slug: "unknown",
            label: "Unknown Token Type",
            provider: "Unknown",
          )
        end


        SecretScanning::Models::Secret.new(
          type: secret.type,
          fingerprint: secret.fingerprint,
          locations: secret.locations.map do |location|
            SecretScanning::Models::Location.new(
              commit_oid: location.commit_oid,
              blob_oid: location.blob_oid,
              path: location.path,
              start_line: location.start_line,
              end_line: location.end_line,
              start_line_byte_position: location.start_line_byte_position,
              end_line_byte_position: location.end_line_byte_position,
            )
          end,
          token_metadata: token_metadata,
          bypass_placeholder_ksuid: secret.bypass_placeholder_ksuid
        )
      end

      sig { params(placeholder: GitHub::Proto::SecretScanning::Scans::V1::BypassPlaceholder).returns(SecretScanning::Models::BypassPlaceholder) }
      def self.from_proto_bypass_placeholder(placeholder)
        metadata = placeholder.token_metadata
        token_metadata = if metadata != nil
          SecretScanning::Models::TokenMetadata.new(
          token_type: metadata.token_type,
          slug: metadata.slug,
          label: metadata.label,
          provider: metadata.provider,
        )
        else
          SecretScanning::Models::TokenMetadata.new(
            token_type: placeholder.token_type,
            slug: "unknown",
            label: "Unknown Token Type",
            provider: "Unknown",
          )
        end

        SecretScanning::Models::BypassPlaceholder.new(
          ksuid: placeholder.ksuid,
          token_type: placeholder.token_type,
          token_metadata: token_metadata,
          actor_id: placeholder.actor_id,
          signature: placeholder.signature,
        )
      end
    end
  end
end
