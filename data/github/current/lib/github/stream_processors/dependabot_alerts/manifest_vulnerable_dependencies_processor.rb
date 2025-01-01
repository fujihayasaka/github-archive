# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependabotAlerts
      class ManifestVulnerableDependenciesProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependabot_alerts-manifest_vulnerable_dependencies_processor"
        DEFAULT_SUBSCRIBE_TO = /dependabot\.v0\.ManifestVulnerableDependenciesFound\Z/
        DEAD_LETTER_TOPIC = "dependabot.v0.ManifestVulnerableDependenciesFound.DeadLetter"

        include TransientErrorResiliency

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 300.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 305.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = true

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


        # Clear any instance variable that hold message-specific information.
        # That way, we can collect metrics using these instance variables
        # without worrying that they leak between messages.
        set_callback :message, :before, prepend: true do
          T.bind(self, GitHub::StreamProcessors::DependabotAlerts::ManifestVulnerableDependenciesProcessor)

          clear_state_before_message
        end

        # Preload records in fewer queries than if we were to load each record
        # inside the vulnerable dependencies loop.
        set_callback :message, :before do
          T.bind(self, GitHub::StreamProcessors::DependabotAlerts::ManifestVulnerableDependenciesProcessor)

          @preload_records = GitHub.flipper[:dependabot_alerts_repo_alerting_preload_records].enabled?
          preload_records_before_message if @preload_records
        end

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.transient_error_max_retries = 10
          self.dead_letter_topic = DEAD_LETTER_TOPIC
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          GitHub.dogstats.distribution_time("manifest_vulnerable_dependencies_processor.process_message", tags: ["preload_records:#{@preload_records}", "partition:#{message.partition}"]) do
            payload = message.value

            if reason = reason_to_skip_message(payload)
              message.skip(reason)
              return
            end

            range_ids_to_keep = []
            push_id = payload.dig(:push_id, :value)
            pull_request_id = payload.dig(:pull_request_id, :value)
            supersedes_manifest_path = payload.dig(:supersedes_manifest_path, :value)

            payload[:vulnerable_dependencies].each do |dependency|
              dependency[:vulnerable_version_range_ids].each do |vulnerable_version_range_id|
                vulnerable_version_range = load_record(VulnerableVersionRange, vulnerable_version_range_id)
                next unless vulnerable_version_range

                vulnerability = vulnerable_version_range.vulnerability
                next unless vulnerability.alertable?

                range_ids_to_keep << vulnerable_version_range.id
                result, alert =
                  RepositoryVulnerabilityAlert.create_or_reintroduce(
                    vulnerability_id: vulnerability.id,
                    vulnerable_version_range_id: vulnerable_version_range.id,
                    repository_id: @repository.id,
                    vulnerable_manifest_path: payload[:manifest_path],
                    vulnerable_requirements: dependency.dig(:requirements, :value),
                    vulnerability_alerting_event_id: @vulnerability_alerting_event.id,
                    dependency_scope: normalize_dependency_scope(dependency[:scope]),
                    # TODO: Relay the dependency_relationship via hydro
                    #
                    # This asynchronous path for manifest alerting is not used at present, but it may be revived
                    # in future. We should make an effort to avoid leaving this code path broken for the new
                    # Dependency Graph Platform functionality
                    #
                    # See: https://github.com/github/dependency-graph/issues/4317
                    dependency_relationship: "unknown",
                    push_id: push_id,
                    pull_request_id: pull_request_id,
                  )

                GitHub.dogstats.increment(
                  "manifest_vulnerable_dependencies_processor.alert",
                  tags: @vulnerability_alerting_event.datadog_tags + ["result:#{result}", "partition:#{message.partition}"],
                )

                # Only trigger notifications if a brand new alert was created
                # i.e. not reintroduced, ignored, updated, skipped.
                if result == :created
                  T.must(alert).trigger_notifications(vulnerability_alerting_event: @vulnerability_alerting_event)
                end
              end
            end

            fixable_alerts = @repository.repository_vulnerability_alerts.fixable

            # Mark alerts for manifest paths that are superseded as fixed
            if supersedes_manifest_path
              fixable_alerts.where(vulnerable_manifest_path: supersedes_manifest_path).find_each do |alert|
                alert.fix(reason: "manifest_superseded", push_id:, pull_request_id:)
              end
            end

            fixable_alerts = fixable_alerts.where.not(vulnerable_version_range_id: range_ids_to_keep)

            # Mark alerts that are no longer vulnerable as fixed
            fixable_alerts.where(vulnerable_manifest_path: payload[:manifest_path]).find_each do |alert|
              alert.fix(reason: "dependency_changed", push_id:, pull_request_id:)
            end
          end
        ensure
          # Try to track progress regardless of whether a manifest was processed.
          # As long as we attempted to process the manifest, that effort should
          # count toward the alerting event's completion. But first, we need
          # to be sure that TransientErrorResiliency isn't retrying a failed
          # message which could cause us to report *too much* progress!
          on_first_try do
            @vulnerability_alerting_event&.progress&.increment_numerator
          end
        end

        private

        def preload_records_before_message
          GitHub.dogstats.distribution_time("manifest_vulnerable_dependencies_processor.preload_records_before_message", tags: ["partition:#{current_message.partition}"]) do
            payload = current_message.value

            vulnerable_version_range_ids =
              payload[:vulnerable_dependencies].flat_map { |d| d[:vulnerable_version_range_ids] }

            vulnerable_version_ranges =
              VulnerableVersionRange
                .where(id: vulnerable_version_range_ids)
                .preload(vulnerability: :vulnerable_version_ranges) # for VulnerableVersionRange#vulnerability.alertable?
                .index_by(&:id)

            @preloaded_records = {
              VulnerableVersionRange => vulnerable_version_ranges,
            }
          end
        end

        def load_record(record_class, record_id)
          if @preload_records
            preloaded_record = @preloaded_records.dig(record_class, record_id)
            return preloaded_record if preloaded_record
          end

          case record_class.name
          when Repository.name
            Repositories::Public.find_active(record_id)
          when VulnerabilityAlertingEvent.name, VulnerableVersionRange.name
            record_class.find_by(id: record_id)
          end
        end

        def clear_state_before_message
          @first_try = true
          @repository = nil
          @vulnerability_alerting_event = nil
        end

        def reason_to_skip_message(payload)
          # Go get the vulnerablity alerting event. If it's not
          # there, we can skip the message.
          #
          # We typically want to front-load the inexpensive checks but we need
          # the alerting event to report progress for every message we
          # encounter, even those we skip for other reasons below.
          vulnerability_alerting_event_id = payload[:vulnerability_alerting_event_id]
          unless vulnerability_alerting_event_id > 0
            return :missing_vulnerability_alerting_event_id
          end

          @vulnerability_alerting_event = load_record(VulnerabilityAlertingEvent, vulnerability_alerting_event_id)
          unless @vulnerability_alerting_event
            return :missing_vulnerability_alerting_event
          end

          if @vulnerability_alerting_event.processed?
            return :processed_vulnerability_alerting_event
          end

          # We can skip all messages if Dependabot alerts are disabled in GHES.
          unless SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
            return :alerts_disabled
          end

          # Make sure we have a repository ID in the message. Why wouldn't we?
          repository_id = payload[:repository_id]
          unless repository_id > 0
            return :missing_repository_id
          end

          manifest_path = payload[:manifest_path]
          unless manifest_path.present?
            return :missing_manifest_path
          end

          # We save the most expensive checks for last so we can avoid
          # performing unnecessary database queries.
          #
          # Go get the repository. If it's not there, we can skip the message.
          @repository = load_record(Repository, repository_id)
          unless @repository
            return :missing_repository
          end

          # We only process a repository's alerts if it has alerts enabled.
          unless @repository.vulnerability_alerts_enabled?
            return :alerts_disabled
          end

          # If we made it here, there's no reason to skip. Process on!
          nil
        end

        def normalize_dependency_scope(dependency_scope)
          if dependency_scope == :UNKNOWN
            GitHub.logger.info(
              "Processed vulnerable dependency with unknown dependency scope",
              "gh.security_alerts.vulnerability_alerting_event.id": @vulnerability_alerting_event.id,
            )
            nil
          else
            dependency_scope.downcase
          end
        end

        def on_first_try
          yield if @first_try
        ensure
          @first_try = false
        end
      end
    end
  end
end
