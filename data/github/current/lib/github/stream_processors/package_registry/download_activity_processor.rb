# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module PackageRegistry
      class DownloadActivityProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "download_activity_processor"
        DEFAULT_SUBSCRIBE_TO = /package_registry\.v0\.PackageVersionDownloaded\Z/

        options[:min_bytes] = 1.bytes
        options[:max_wait_time] = 0.2.seconds
        options[:max_bytes_per_partition] = 10.kilobytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        def process_message(message)
          track_package_download_activity(message, package_id(message), version_id(message), downloaded_at(message))
          sync_download_count_v2_migration(message)
        end

        def track_package_download_activity(message, package_id, version_id, downloaded_at)
          # Skip incrementing package version download count on retry
          # https://github.com/github/c2c-package-registry/issues/5703
          return unless package_id && version_id && downloaded_at && !is_retry?(message)
          Registry::PackageDownloadActivity.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            Registry::PackageDownloadActivity.track(
              package_id,
              version_id,
              downloaded_at.change(min: 0, sec: 0),
            )
          end
        rescue ActiveRecord::ActiveRecordError => err
          Failbot.report(err)
          GitHub.dogstats.increment("package_version_downloaded_processor.track_download_error")
        end

        def package_id(message)
          message.value.dig(:package, :id)
        end

        def version_id(message)
          message.value.dig(:version, :id)
        end

        def downloaded_at(message)
          message_seconds = message.value.dig(:downloaded_at, :seconds)
          if message_seconds.present?
            Time.at(message_seconds)
          else
            Time.now.utc
          end
        end

        def is_retry?(message)
          retry_count = message.value.dig(:retry_count)
          retry_count.present? && retry_count > 0
        end

        def sync_download_count_v2_migration(message)
          package_name = message.value.dig(:package, :name)
          package_type = message.value.dig(:package, :registry_type)
          namespace = get_owner_login(message)
          version_name = message.value.dig(:version, :version)
          package_id = package_id(message)
          version_id = version_id(message)
          if !is_valid_registry_type?(package_type)
            message.skip("not a valid registry type")
            return
          end
          log("download_activity_processor: sync download count v2 migration for package_id: #{package_id}, version_id: #{version_id}, package_type: #{package_type.to_sym}")
          package_version = Registry::PackageVersion.find_by(id: version_id)

          if GitHub.enterprise? && package_type.to_sym == :DOCKER && package_version.present? && package_version.migrated? && should_sync_download_count(package_version)
            repo_name = package_version.package&.repository&.name
            v2_package_name = "#{repo_name}/#{package_name}"
            GitHub.logger.info(
              "Syncing download count for docker",
              "code.function" => __method__,
              "code.namespace" => self.class.name,
              "gh.registry.namespace" => namespace,
              "gh.registry.package_name" => v2_package_name,
              "gh.registry.version_name" => version_name,
            )
            rms_migrator_client.emit_migration_download_event?(namespace: namespace, package_name: v2_package_name, version_name: version_name)
            return
          end

          if  package_version.present? && (package_type.to_sym == :NPM || package_type.to_sym == :NUGET || package_type.to_sym == :RUBYGEMS)
            if package_version.migrated?
              rms_migrator_client.sync_download_count?(namespace: namespace, package_name: package_name, version_name: version_name, ecosystem: package_type.to_sym)
            elsif package_version.migration_in_progress?
              retry_count = message.value.dig(:retry_count) || 0
              if retry_count <= 1000
                GitHub.logger.info(
                  "Requeueing download activity event",
                  "code.function" => __method__,
                  "code.namespace" => self.class.name,
                  "gh.registry.package_id" => package_id,
                  "gh.registry.version_id" => version_id,
                  "gh.registry.retry_count" => retry_count,
                )
                cloned_message = {
                  request_context: message.value.dig(:request_context),
                  actor: message.value.dig(:actor),
                  package: message.value.dig(:package),
                  version: message.value.dig(:version),
                  storage_service: message.value.dig(:storage_service),
                  downloaded_at: downloaded_at(message),
                  user_agent: message.value.dig(:user_agent),
                  via_actions: message.value.dig(:via_actions),
                  file: message.value.dig(:file),
                  event_id: message.value.dig(:event_id),
                  installation_id: message.value.dig(:installation_id),
                  oauth_application_id: message.value.dig(:oauth_application_id),
                  retry_count: retry_count + 1,
                }
                GlobalInstrumenter.instrument("package_registry.package_version_downloaded", cloned_message)
              else
                GitHub.logger.info(
                  "Retry limit exceeded",
                  "code.function" => __method__,
                  "code.namespace" => self.class.name,
                  "gh.registry.owner_namespace" => namespace,
                  "gh.registry.package_id" => package_id,
                  "gh.registry.version_id" => version_id,
                )
                Failbot.report(
                  StandardError.new("Download count sync retry limit exceeded."),
                  { package_id: package_id,
                    version_id: version_id,
                    owner: namespace,
                    retry_count: retry_count,
                  }
                )
                message.skip("retry limit exceeded")
              end
            end
          end
        end

        def rms_migrator_client
          @rms_migrator_client ||= ::PackageRegistry::Twirp.migrator_client
        end

        def get_owner_login(message)
          if message.value.dig(:package, :owner_org)
            message.value.dig(:package, :owner_org, :login)
          else
            message.value.dig(:package, :owner_user, :login)
          end
        end

        def is_valid_registry_type?(package_type)
          return true if package_type.to_sym == :NPM || package_type.to_sym == :DOCKER || package_type.to_sym == :NUGET || package_type.to_sym == :RUBYGEMS
          false
        end

        def get_total_downloads(package_version)
          count = package_version&.total_download_count
          return count.to_i if count.present?
          0
        end

        def should_sync_download_count(package_version)
          total_downloads = get_total_downloads(package_version)
          if total_downloads > 0 && package_version.files_count > 0
            mod = total_downloads.modulo(package_version.files_count)
            return true if mod == 0
          end
          false
        end

      end
    end
  end
end
