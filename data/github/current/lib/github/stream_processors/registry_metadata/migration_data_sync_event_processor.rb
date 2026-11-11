# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class MigrationDataSyncEventProcessor < SingleMessageProcessor

        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "package-registry-ghes-migration_data_sync"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.MigrationDataSyncEvent\Z/

        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds

        options[:start_from_beginning] = false

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        def process_message(message)
          return if message.value.dig(:event_type) != :SHA_UPDATE

          package_id = message.value.dig(:package_id)
          tag = message.value.dig(:tag_name)
          platform = message.value.dig(:platform)

          log("sha_update event processor: processing event with package_id #{package_id} and tag #{tag}")

          version ||= Registry::PackageVersion.find_by(registry_package_id: package_id, version: tag, platform: platform)
          if version.nil?
            message.skip(:verson_not_found)
            return
          end

          log("sha_update event processor: updating versionID #{version.id}, versionTag: #{version.version} for migration")
          version.migration_state = "unmigrated"

          begin
            with_write { version.save!(touch: false) }
           rescue ActiveRecord::RecordInvalid => e
             Failbot.report(e)
             return
          end

          log("sha_update event processor: queueing packageID #{package_id} for migration")
          ::Packages::Migration::MigratePackageJob.perform_later(package_id)
        end
      end
    end
  end
end
