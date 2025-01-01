# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class PackagePublishedAuditProcessor < SingleMessageProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "rms_package_published_audit_processor"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.PackagePublished\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 1.megabyte
        options[:start_from_beginning] = false

        # Initialize the PackagePublishedAuditProcessor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Publish V2 package publish event to the audit log
        #
        # message - The package published hydro message
        #
        # Returns nothing
        def process_message(message)

          audit_message = get_audit_message(message)

          return if audit_message.skipped?

          instrument(audit_message)
        end

        private

        def get_audit_message(original_message)
          audit_message = ::PackageRegistry::AuditMessage.new(original_message) do |msg|
            actor = ::PackageRegistry::Instrumentation.get_actor(actor_id: msg.get(:actor_id), actor_type: msg.get(:actor_type))
            msg.actor_id = actor&.id
            msg.actor = actor&.display_login
            msg.actor_type = msg.get(:actor_type, skip_if_missing: false)
            msg.org_id = msg.get(:owner_id)
            msg.org = msg.get(:package, :display_login)
            msg.package_id = msg.get(:package, :id)
            msg.package = msg.get(:package, :name)
            msg.ecosystem = msg.get(:package, :ecosystem)
            msg.version_count = msg.get(:version_count, skip_if_missing: false)
            msg.storage_bytes = msg.get(:storage_bytes, skip_if_missing: false)
            msg.is_republished = msg.get(:republished)
            msg.published_at_seconds = msg.get(:package, :updated_at, :seconds)
            msg.published_at_nanos = msg.get(:package, :updated_at, :nanos)
          end

          audit_message.skip("missing actor") if audit_message.actor.nil?
          audit_message
        end

        def instrument(audit_message)
          ::PackageRegistry::Instrumentation.package_published(
            actor_id: audit_message.actor_id,
            actor: audit_message.actor,
            org_id: audit_message.org_id,
            org: audit_message.org,
            package_id: audit_message.package_id,
            package: audit_message.package,
            ecosystem: audit_message.ecosystem,
            version_count: audit_message.version_count,
            storage_bytes: audit_message.storage_bytes,
            is_republished: audit_message.is_republished,
            published_time: audit_message.published_time
          )
        end

      end
    end
  end
end
