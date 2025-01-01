# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class PackageDeleteSyncProcessor < BaseProcessor

        DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-package_registry-package_delete_sync_processor", String)
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageDeleted\Z/

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
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        sig { returns(::PackageRegistry::Twirp::MetadataClient) }
        def v2_client
          @client ||= T.let(::PackageRegistry::Twirp.metadata_client, T.nilable(::PackageRegistry::Twirp::MetadataClient))
        end

        # Public: Process a single Hydro message
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          package_type = message.value.dig(:package, :registry_type)
          if !is_valid_registry_type?(package_type)
            return message.skip("not a valid registry type")
          end

          repository_name = message.value.dig(:package, :repository, :name)

          if repository_name.blank?
            return message.skip("repository_name is blank")
          end

          package_id = message.value.dig(:package, :id).to_i

          if package_id.zero? || package_id.negative?
            return message.skip("Invalid package_id: #{package_id}")
          end

          package_name = message.value.dig(:package, :name).to_s

          if package_name.blank?
            return message.skip("package_name is blank")
          end

          namespace = get_owner_login(message)

          if namespace.blank?
            return message.skip("namespace is blank")
          end

          owner_id = message.value.dig(:package, :owner_id).to_i

          if owner_id.zero? || owner_id.negative?
            return message.skip("Invalid owner_id: #{owner_id}")
          end

          version_count = message.value.dig(:package, :version_count, :value).to_i
          user = User.find_by(id: owner_id)
          if user.nil?
            return message.skip("missing_owner")
          end

          if package_type == :DOCKER
            versions_migrated_count = Registry::Package.any_deleted_version_migrated("docker").where("registry_packages.id = ?", package_id).count
            package_name = "%s/%s" % [repository_name, package_name]
            package_type = "container"
          else
            package_type = package_type.to_s.downcase
            versions_migrated_count = Registry::Package.any_deleted_version_migrated(package_type).where("registry_packages.id = ?", package_id).count
          end

          GitHub.logger.info(
            "Syncing V1 package delete to V2 started",
            "code.namespace" => self.class.name,
            "code.function" => "process_message",
            "gh.registry.package.type" => package_type,
            "gh.registry.package.repository_name" => repository_name,
            "gh.registry.package.id" => package_id,
            "gh.registry.package.namespace" => namespace,
            "gh.registry.package.owner_id" => owner_id,
            "gh.user.id" => user.id,
            "gh.registry.package.version_count" => version_count,
            "gh.registry.package.versions_migrated_count" => versions_migrated_count
          )

          # if migration has started and there is atleast one package version is migrated to v2, delete the package from v2
          if versions_migrated_count > 0
            begin
              v2_client.delete_package(namespace: namespace, name: package_name, ecosystem: package_type, actor: user)
            rescue ::PackageRegistry::Twirp::Error => e
              Failbot.report(e)

              GitHub.logger.info(
                "Syncing V1 package delete to V2 failed",
                "code.namespace" => self.class.name,
                "code.function" => "process_message",
                "gh.registry.package.type" => package_type,
                "gh.registry.package.repository_name" => repository_name,
                "gh.registry.package.id" => package_id,
                "gh.registry.package.namespace" => namespace,
                "gh.registry.package.owner_id" => owner_id,
                "gh.user.id" => user.id,
                "gh.registry.package.version_count" => version_count,
                "gh.registry.package.versions_migrated_count" => versions_migrated_count
              )
            else
              GitHub.logger.info(
                "Syncing V1 package delete to V2 completed",
                "code.namespace" => self.class.name,
                "code.function" => "process_message",
                "gh.registry.package.type" => package_type,
                "gh.registry.package.repository_name" => repository_name,
                "gh.registry.package.id" => package_id,
                "gh.registry.package.namespace" => namespace,
                "gh.registry.package.owner_id" => owner_id,
                "gh.user.id" => user.id,
                "gh.registry.package.version_count" => version_count,
                "gh.registry.package.versions_migrated_count" => versions_migrated_count
              )
            end
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).returns(String) }
        def get_owner_login(message)
          if message.value.dig(:package, :owner_org)
            message.value.dig(:package, :owner_org, :login)
          else
            message.value.dig(:package, :owner_user, :login)
          end
        end

        sig { params(package_type: T.any(Symbol, String)).returns(T::Boolean) }
        def is_valid_registry_type?(package_type)
          %w[NPM NUGET RUBYGEMS].include?(package_type.to_s) || (package_type == :DOCKER && GitHub.enterprise?)
        end

      end
    end
  end
end
