# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class SyncV1PackageVersionDeleteToV2Processor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-package_registry-sync_v1_package_version_delete_to_v2_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageVersionDeleted\Z/

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

        def v2_client
          @client ||= ::PackageRegistry::Twirp.metadata_client
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          if !is_valid_registry_type?(message)
            return message.skip("not a valid registry type")
          end

          package_type = message.value.dig(:package, :registry_type)
          repository_name = message.value.dig(:package, :repository, :name)

          if repository_name.blank?
            return message.skip("Repository name is blank")
          end

          package_name = message.value.dig(:package, :name)

          if package_name.blank?
            return message.skip("Package name is blank")
          end

          package_id = message.value.dig(:package, :id).to_i

          if package_id.zero?
            return message.skip("Package id is zero")
          end

          version = message.value.dig(:version, :version)
          id = message.value.dig(:version, :id)

          namespace = get_owner_login(message)

          if namespace.blank?
            return message.skip("Namespace is blank")
          end

          owner_id = message.value.dig(:package, :owner_id).to_i

          if  owner_id.zero?
            return message.skip("Owner id is zero")
          end

          user = User.find_by(id: owner_id)

          if user.nil?
            return message.skip("user not found")
          end

          GitHub.logger.info(
            "Syncing V1 version delete to V2 started",
            "code.function" => __method__,
            "code.namespace" => self.class.name,
            "gh.registry.package_type" => package_type,
            "gh.registry.repository_name" => repository_name,
            "gh.registry.package_name" => package_name,
            "gh.registry.package_id" => package_id,
            "gh.registry.version_id" => id,
            "gh.registry.package_namespace" => namespace,
            "gh.registry.owner_id" => owner_id,
            "gh.registry.user" => user,
          )

          package_version = Registry::PackageVersion.find_by(id: id)
          # Delete the version from container registry only if the version is migrated in docker but the complete package is still not fully migrated
          if package_version.present? && package_version.migrated? && !package_version.package.migrated?
            if package_type == :DOCKER
              package_type = "container"
              package_name = "%s/%s" % [repository_name, package_name]
            else
              package_type = package_type.to_s.downcase
            end
            resp = v2_client.get_package_metadata(namespace: namespace, name: package_name, ecosystem: package_type, actor: user, version_limit: 2)

            if resp&.package.nil?
              message.skip("Package not found in RMS")
              return
            end
            begin
              v2_client.delete_package_version(namespace: namespace, name: package_name, ecosystem: package_type, actor: user, version: version, mode: :soft)
            rescue ::PackageRegistry::Twirp::BaseError => e
              GitHub.logger.error(
                e,
                "code.function" => __method__,
                "code.namespace" => self.class.name,
                "gh.registry.package_type" => package_type,
                "gh.registry.repository_name" => repository_name,
                "gh.registry.package_name" => package_name,
                "gh.registry.package_id" => package_id,
                "gh.registry.version_id" => id,
                "gh.registry.package_namespace" => namespace,
                "gh.registry.owner_id" => owner_id,
                "gh.registry.user" => user,
              )
            else
              GitHub.logger.info(
                "Syncing V1 version delete to V2 completed",
                "code.function" => __method__,
                "code.namespace" => self.class.name,
                "gh.registry.package_type" => package_type,
                "gh.registry.repository_name" => repository_name,
                "gh.registry.package_name" => package_name,
                "gh.registry.package_id" => package_id,
                "gh.registry.version_id" => id,
                "gh.registry.package_namespace" => namespace,
                "gh.registry.owner_id" => owner_id,
                "gh.registry.user" => user,
              )
            end
          end
        end

        def get_owner_login(message)
          if message.value.dig(:package, :owner_org)
            message.value.dig(:package, :owner_org, :login)
          else
            message.value.dig(:package, :owner_user, :login)
          end
        end

        def is_valid_registry_type?(message)
          package_type = message.value.dig(:package, :registry_type)
          if %w[NPM NUGET RUBYGEMS].include?(package_type.to_s) || (package_type == :DOCKER && GitHub.enterprise?)
            return true
          end
          false
        end
      end
    end
  end
end
