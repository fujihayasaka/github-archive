# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SecretScanning
      class ScanCompletionProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-secret_scanning_scan_completion_processor"
        DEFAULT_SUBSCRIBE_TO = /token_scanning_service\.v0\.ScanCompleteEvent\Z/

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
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          start = Time.now
          success = false

          begin
            process_events(message)
            success = true
          ensure
            duration_ms = (Time.now - start) * 1000
            since_requested_ms = (Time.now - Time.at(message.timestamp)).to_f * 1000
            tags = [
              "topic:#{message.topic}",
              "processor:scan_completion",
              "success:#{success}",
            ]

            GitHub.dogstats.distribution("secret_scanning.webhook_processor.duration", duration_ms, tags: tags)
            GitHub.dogstats.distribution("secret_scanning.webhook_processor.duration.since_requested", since_requested_ms, tags: tags)
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_events(message)
          repo_id = message.value[:repository_id]
          repo = T.let(nil, T.nilable(Repository))

          with_read do
            repo = Repository.find_by(id: repo_id)
          end

          if repo.nil?
            GitHub.logger.info(
              "Repository not found, skipping message",
              "code.namespace": self.class.name,
              "gh.repo.id": repo_id
            )

            return
          end

          unless repo.advanced_security_enabled?
            GitHub.logger.info(
              "Advanced security is not purchased/enabled on repo, skipping message",
              "code.namespace": self.class.name,
              "gh.repo.id": repo_id
            )

            return
          end

          unless ::SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
            GitHub.logger.info(
              "Secret scanning not enabled on repo, skipping message",
              "code.namespace": self.class.name,
              "gh.repo.id": repo_id
            )

            return
          end

          payload = {
            repo: repo,
            repo_id: repo.id,
            org: repo.owner,
            org_id: repo.owner_id,
            business: repo.owner&.business,
            business_id: repo.owner&.business&.id,
            source: message.value[:source_slug],
            type: message.value[:type_slug],
            started_at: Time.at(message.value[:started_at][:seconds]),
            completed_at: Time.at(message.value[:completed_at][:seconds]),
          }

          event = Hook::Event::SecretScanningScanEvent.new(
            repository_id: repo.id,
            source: message.value[:source],
            type: message.value[:type],
            source_slug: message.value[:source_slug],
            type_slug: message.value[:type_slug],
            started_at: message.value[:started_at],
            completed_at: message.value[:completed_at],
          )

          if message.value[:type] == :TYPE_PATTERN_VERSION_BACKFILL
            event.secret_types = message.value[:secret_types]
            payload[:secret_types] = message.value[:secret_types]
          elsif message.value[:type] == :TYPE_CUSTOM_PATTERN_BACKFILL
            event.custom_pattern_name = message.value[:pattern_name]
            event.custom_pattern_scope = message.value[:pattern_scope]
            payload[:custom_pattern_name] = message.value[:pattern_name]
            payload[:custom_pattern_scope] = pattern_scope(message.value[:pattern_scope])
          end

          GitHub.instrument("secret_scanning_scan.completed", payload)
          event.deliver_later
        end

        sig { params(scope: Symbol).returns(String) }
        def pattern_scope(scope)
          case scope
          when :SCOPE_REPOSITORY
            "repository"
          when :SCOPE_ORGANIZATION
            "organization"
          when :SCOPE_ENTERPRISE
            "enterprise"
          else
            "unknown"
          end
        end
      end
    end
  end
end
