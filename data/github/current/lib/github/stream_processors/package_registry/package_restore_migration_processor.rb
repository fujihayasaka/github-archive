# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageRestoreMigrationProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-package_registry-package_restore_migration_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackagePublished\Z/

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false

        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          if is_restore_event?(message) && is_valid_registry_type?(message)
            restore_package_v2(message)
          else
            message.skip("not a restore event or not a valid registry type")
          end
        end

        def v2_client
          @client ||= ::PackageRegistry::Twirp.metadata_client
        end

        def restore_package_v2(message)
          package_name = message.value.dig(:package_deleted_name)
          package_type = message.value.dig(:package, :registry_type)
          package_ecosystem = package_type == :DOCKER ? :CONTAINER : package_type
          repository_name = message.value.dig(:package, :repository, :name)
          owner_login = get_owner_login(message)
          package_id = message.value.dig(:package, :id)
          actor_id = message.value.dig(:actor, :id)
          package = Registry::Package.find_by(id: package_id)
          if package.present? && package.partially_migrated?
            package_name = "%s/%s" % [repository_name, package_name] if package_ecosystem == :CONTAINER
            actor = User.find_by(id: actor_id)
            log("package_restore_migration_processor: processing event for package_id: #{package_id}")
            begin
              v2_client.restore_package(namespace: owner_login, name: package_name, ecosystem: package_ecosystem.to_sym, actor: actor)
            rescue ::PackageRegistry::Twirp::PermissionDeniedError
              log("package_restore_migration_processor: package not found for package_id: #{package_id} - hydro message: #{message.topic} - partition #{message.partition} - offset: #{message.offset}")
              Failbot.report(e)
              message.error(e)
            rescue ::PackageRegistry::Twirp::AlreadyExistsError
              log("package_restore_migration_processor: Active package already exists with given name for package_id: #{package_id} - hydro message: #{message.topic} - partition #{message.partition} - offset: #{message.offset}")
              Failbot.report(e)
              message.error(e)
            rescue ::PackageRegistry::Twirp::Error => e
              log("package_restore_migration_processor: getting exception for package_id: #{package_id}, version_id: #{version_id} - hydro message: #{message.topic} - partition #{message.partition} - offset: #{message.offset}")
              Failbot.report(e)
              message.error(e)
            end
          else
            message.skip("package not partially migrated")
          end
        end

        def is_restore_event?(message)
          return true if message.value.dig(:republished)
          false
        end

        def is_valid_registry_type?(message)
          package_type = message.value.dig(:package, :registry_type)
          if %w[NPM NUGET RUBYGEMS].include?(package_type.to_s) || (package_type == :DOCKER && GitHub.enterprise?)
            return true
          end
          false
        end

        def get_owner_login(message)
          if message.value.dig(:package, :owner_org)
            message.value.dig(:package, :owner_org, :login)
          else
            message.value.dig(:package, :owner_user, :login)
          end
        end
      end
    end
  end
end
