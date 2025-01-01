# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageDeletedAuditProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "package_deleted_audit_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageDeleted\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the PackageDeletedAuditProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Publish V1 package deleted event to audit log.
        #
        # message - The package deleted hydro message
        #
        # Returns nothing
        def process_message(message)

          audit_message = get_audit_message(message)

          return if audit_message.skipped?

          instrument(audit_message)
        end

        private

        def get_audit_message(original_message)
          ::PackageRegistry::AuditMessage.new(original_message) do |msg|
            msg.actor_id = msg.get(:actor, :id)
            msg.actor = msg.get(:actor, :login)
            msg.org_id = msg.get(:package, :owner_org, :id)
            msg.org = msg.get(:package, :owner_org, :login)
            msg.repo_id = msg.get(:package, :repository, :id)
            msg.repo = msg.get(:package, :repository, :name)
            msg.package_id = msg.get(:package, :id)
            msg.package = msg.get(:package, :name)
            msg.ecosystem = msg.get(:package, :registry_type)
            msg.version_count = msg.get(:package, :version_count, :value, skip_if_missing: false)
            msg.storage_bytes = msg.get(:package, :total_size, :value, skip_if_missing: false)
            msg.deleted_at_seconds = msg.get(:deleted_at, :seconds)
            msg.deleted_at_nanos = msg.get(:deleted_at, :nanos)
          end
        end

        def instrument(audit_message)
          ::PackageRegistry::Instrumentation.package_deleted(
            actor_id: audit_message.actor_id,
            actor: audit_message.actor,
            org_id: audit_message.org_id,
            org: audit_message.org,
            repo_id: audit_message.repo_id,
            repo: audit_message.repo,
            package_id: audit_message.package_id,
            package: audit_message.package,
            ecosystem: audit_message.ecosystem,
            version_count: audit_message.version_count,
            storage_bytes: audit_message.storage_bytes,
            deleted_time: audit_message.deleted_time
          )
        end

      end
    end
  end
end
