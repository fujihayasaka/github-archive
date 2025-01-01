# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageVersionPublishedAuditProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "package_version_published_audit_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageVersionPublished\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 100.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Initialize the PackageVersionPublishedAuditProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Emit V1 package version published event to audit log. The 'republished' flag in the message
        # indicates whether the version is a first publish or a republish/restore
        #
        # message - The package version published hydro message
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
            msg.should_skip = msg.get(:bulk_publish, skip_if_missing: false)
            msg.actor_id = msg.get(:actor, :id)
            msg.actor = msg.get(:actor, :login)
            msg.org_id = msg.get(:package, :owner_org, :id)
            msg.org = msg.get(:package, :owner_org, :login)
            msg.repo_id = msg.get(:package, :repository, :id)
            msg.repo = msg.get(:package, :repository, :name)
            msg.package_id = msg.get(:package, :id)
            msg.package = msg.get(:package, :name)
            msg.ecosystem = msg.get(:package, :registry_type)
            msg.storage_bytes = msg.get(:version, :package_size)
            msg.version_id = msg.get(:version, :id)
            msg.version = msg.get(:version, :version)
            msg.published_at_seconds = msg.get(:published_at, :seconds)
            msg.published_at_nanos = msg.get(:published_at, :nanos)
            msg.is_republished = msg.get(:republished)
          end
        end

        def instrument(audit_message)
          ::PackageRegistry::Instrumentation.package_version_published(
              actor_id: audit_message.actor_id,
              actor: audit_message.actor,
              org_id: audit_message.org_id,
              org: audit_message.org,
              repo_id: audit_message.repo_id,
              repo: audit_message.repo,
              package_id: audit_message.package_id,
              package: audit_message.package,
              ecosystem: audit_message.ecosystem,
              storage_bytes: audit_message.storage_bytes,
              version_id: audit_message.version_id,
              version: audit_message.version,
              published_time: audit_message.published_time,
              republished: audit_message.is_republished
          )
        end
      end
    end
  end
end
