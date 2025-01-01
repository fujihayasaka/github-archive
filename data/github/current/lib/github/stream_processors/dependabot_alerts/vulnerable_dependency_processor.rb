# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependabotAlerts
      class VulnerableDependencyProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependabot_alerts-vulnerable_dependency_processor"
        DEFAULT_SUBSCRIBE_TO = /dependabot\.v0\.VulnerableDependencyFound\Z/
        DEAD_LETTER_TOPIC = "dependabot.v0.VulnerableDependencyFound.DeadLetter"

        include TransientErrorResiliency

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
        #
        # An individual VulnerableDependencyFound message (as of this writing)
        # takes ~200ms to process. Targeting 30s for processing a batch comes
        # to 150 messages per batch. Message size is fairly consistent at just
        # under 0.5KB. So let's fetch 75KB of data per batch.
        options[:max_bytes_per_partition] = 75.kilobytes

        set_callback :batch, :before, :before_batch
        set_callback :batch, :after, :after_batch

        # this should be very first thing we do as we need this to report progress
        set_callback :message, :before, :set_vulnerable_version_range_alerting_process

        # this needs to be an around callback as we need to be able rescue any exceptions
        # from the message processing and still report progress
        set_callback :message, :around, :track_progress

        set_callback :message, :before, :set_repository
        set_callback :message, :around, :tenant_handling, if: -> { GitHub.multi_tenant_enterprise? }

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.transient_error_max_retries = 10
          self.dead_letter_topic = DEAD_LETTER_TOPIC
        end

        def batching?
          true
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          if reason = reason_to_skip_message(message)
            message.skip(reason)
            return
          end

          payload = message.value

          with_write do
            result, alert =
              RepositoryVulnerabilityAlert.create_or_reintroduce(
                vulnerability_id: @vulnerability.id,
                vulnerable_version_range_id: @vulnerable_version_range.id,
                repository_id: @repository.id,
                vulnerable_manifest_path: payload.dig(:vulnerable_dependency, :manifest_path),
                vulnerable_requirements: payload.dig(:vulnerable_dependency, :requirements, :value),
                vulnerability_alerting_event_id: @vulnerability_alerting_event.id,
                dependency_scope: normalize_dependency_scope(payload.dig(:vulnerable_dependency, :scope)),
                dependency_relationship: normalize_dependency_relationship(payload.dig(:vulnerable_dependency, :relationship)),
                low_priority_throttle: true,
              )

            GitHub.dogstats.increment(
              "vulnerable_dependency_processor.alert",
              tags: @vulnerable_version_range_alerting_process.datadog_tags + ["result:#{result}"],
            )

            # Only trigger notifications if a brand new alert was created
            # i.e. not reintroduced, ignored, updated, skipped.
            if result == :auto_reopened || result == :created
              Dependabot::RepositoryVulnerabilityCreatedJob.enqueue(alert)
              alert&.trigger_notifications(vulnerability_alerting_event: @vulnerability_alerting_event) if result == :created
            end
          end
        end

        private

        def set_vulnerable_version_range_alerting_process
          # Clear instance variables set while processing the previous message.
          @vulnerable_version_range_alerting_process = nil

          # Go get the vulnerable version range alerting process. If it's not
          # there, we can skip the message.
          #
          # We typically want to front-load the inexpensive checks but we need
          # the alerting process to report progress for every message we
          # encounter, even those we skip for other reasons.
          @vulnerable_version_range_alerting_process =
            VulnerableVersionRangeAlertingProcess.find_by(id: current_message.value[:vulnerable_version_range_alerting_process_id])
          unless @vulnerable_version_range_alerting_process
            current_message.skip(:missing_vulnerable_version_range_alerting_process)
            throw :abort
          end
        end

        def track_progress
          # Try to track progress regardless of whether an alert was created.
          # As long as we attempted to process an alert, that effort should
          # count toward the alerting process's completion. But first, we need
          # to be sure that TransientErrorResiliency isn't retrying a failed
          # message which could cause us to report *too much* progress!
          yield
        ensure
          on_first_try(current_message) do
            message_counts_by_process[@vulnerable_version_range_alerting_process] += 1
          end
        end

        def set_repository
          # Clear instance variables set while processing the previous message.
          @repository = nil

          # Make sure we have a repository ID in the message. Why wouldn't we?
          repository_id = current_message.value.dig(:repository_id)
          unless repository_id > 0
            current_message.skip(:missing_repository_id)
            throw :abort
          end

          # Go get the repository. If it's not there, we can skip the message.
          @repository = Repositories::Public.find_active(repository_id)
          unless @repository
            current_message.skip(:missing_repository)
            throw :abort
          end
        end

        def tenant_handling
          business = GitHub::CurrentTenant.unscope { @repository.owner&.business || @repository.enterprise_managed_business }
          GitHub::CurrentTenant.set(business) { yield }
        end

        def before_batch
          message_ids_tried.clear
          message_counts_by_process.clear

          GitHub.dogstats.distribution("vulnerable_dependency_processor.batch_size", current_batch.size)
        end

        def after_batch
          message_counts_by_process.each do |process, message_count|
            next unless process && message_count > 0
            process.progress.increment_numerator(by: message_count)
          end
        end

        def reason_to_skip_message(message)
          # Clear instance variables set while processing the previous message.
          @vulnerability = nil
          @vulnerable_version_range = nil
          @vulnerability_alerting_event = nil

          payload = message.value

          # # We can skip all messages if Dependabot alerts are disabled in GHES.
          unless SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
            return :alerts_disabled
          end

          # We skip messages that have multiple vulnerable version range IDs.
          vulnerable_version_range_ids =
            payload.dig(:vulnerable_dependency, :vulnerable_version_range_ids)
          if vulnerable_version_range_ids&.count.to_i > 1
            return :multiple_vulnerable_version_range_ids
          end

          # We only process messages that have exactly one valid vulnerable
          # version range ID.
          vulnerable_version_range_id = vulnerable_version_range_ids&.first
          if vulnerable_version_range_ids.blank? || vulnerable_version_range_id.zero?
            return :missing_vulnerable_version_range_id
          end

          dg_process_manager = DependencyGraph::VulnerabilityScanning::AdvisoryBroadcastProcessManager.from_hydro_enum(
            payload[:dependency_provider]
          )

          # We only process messages that were published after the
          # most recent update to a repository's alerts
          last_processed_at =
            VulnerabilityAlertingEvent.where(repository_id: @repository.id).maximum(:processed_at)
          seconds = payload.dig(:created_at, :seconds)
          nanos = payload.dig(:created_at, :nanos)
          created_at = Time.at(seconds, nanos, :nsec).utc if seconds && nanos
          unless last_processed_at.nil? || created_at.nil? || created_at > last_processed_at
            return :message_published_before_last_update
          end

          # We only update a repository's vulnerability exposure if it has
          # vulnerability alerts enabled.
          unless @repository.vulnerability_alerts_enabled?
            return :alerts_disabled
          end

          # Go get the vulnerability alerting event. If it's not there, we can
          # skip the message.
          @vulnerability_alerting_event =
            VulnerabilityAlertingEvent.find_by(id: payload[:vulnerability_alerting_event_id])
          unless @vulnerability_alerting_event
            return :missing_vulnerability_alerting_event
          end

          # We only process messages for advisory publication events.
          unless @vulnerability_alerting_event.on_process_alerts?
            return :invalid_vulnerability_alerting_event_reason
          end

          # We only process messages if the vulnerable version range exists.
          @vulnerable_version_range =
            VulnerableVersionRange.find_by(id: vulnerable_version_range_id)
          unless @vulnerable_version_range
            return :missing_vulnerable_version_range
          end

          # Go get the vulnerability. If it's not there, we can skip the
          # message.
          @vulnerability = @vulnerable_version_range.vulnerability
          unless @vulnerability
            return :missing_vulnerability
          end

          # We only process alerts for alertable vulnerabilities.
          unless @vulnerability.alertable?
            return :vulnerability_not_alertable
          end

          # We do not need to process the message if this is not the canonical provider for this repository/ecosystem
          unless dg_process_manager.canonical_provider_for?(@repository, @vulnerable_version_range)
            return dg_process_manager.disabled_slug
          end

          # If we made it here, there's no reason to skip. Process on!
          nil
        end

        def normalize_dependency_scope(dependency_scope)
          if dependency_scope == :UNKNOWN
            GitHub.logger.info(
              "Processed vulnerable dependency with unknown dependency scope",
              "gh.security_alerts.vulnerability.id": @vulnerability.id,
              "gh.security_alerts.vulnerability_alerting_event.id": @vulnerability_alerting_event.id,
            )
            nil
          else
            dependency_scope.downcase
          end
        end

        def normalize_dependency_relationship(dependency_relationship)
          case dependency_relationship
          when :DIRECT
            "direct"
          when :INDIRECT
            "transitive"
          when :INCONCLUSIVE
            "inconclusive"
          when :UNKNOWN_DEPENDENCY_RELATIONSHIP
            "unknown"
          else
            GitHub.logger.info(
              "Processed vulnerable dependency with unexpected dependency relationship",
              "gh.security_alerts.vulnerability.id": @vulnerability.id,
              "gh.security_alerts.vulnerability_alerting_event.id": @vulnerability_alerting_event.id,
            )
            "unknown"
          end
        end

        def on_first_try(message)
          yield if message_ids_tried.add?(message.id)
        end

        def message_ids_tried
          @message_ids_tried ||= Set.new
        end

        def message_counts_by_process
          @message_counts_by_process ||= Hash.new(0)
        end
      end
    end
  end
end
