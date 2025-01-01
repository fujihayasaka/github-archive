# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SecretScanning
      class AlertEventsProcessor < BaseProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "alert_events_processor"
        DEFAULT_SUBSCRIBE_TO = /token_scanning_service\.v0\.AlertEvents\Z/

        # This configures how many events are taken from the incoming message.
        # If the number of events within the payload exceeds this value, we will
        # not process those "extra" events.
        # This value is combined with the configurable page size inside the
        # token-scanning-service, which controls how many events to send per page.
        MAX_PROCESSED_ALERT_EVENTS = 1000

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

        # We need to resolve tenant context on multi-tenant (Proxima) instances. However, we are
        # already doing that below using GitHub::CurrentTenant.set(business) do. So, we can safely
        # disable the tenant context requirement here.
        exempt_from_tenant_context_requirement

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # don't batch messages when consuming them.
        # this allow us to post the offset more frequently
        # back to the broker. This should be a default on BaseProcessor soon
        sig { returns(T::Boolean) }
        def batching?
          false
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          success = false
          begin
            process_alert_events(message)
            success = true
          ensure
            GitHub.dogstats.increment("secret_scanning.alert_events_processor.complete", tags: ["success:#{success}"])
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_alert_events(message)
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

          business = GitHub.multi_tenant_enterprise? ? GitHub::CurrentTenant.unscope { repo.owner&.business } : nil

          GitHub::CurrentTenant.set(business) do
            unless ::SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
              GitHub.logger.info(
                "Secret scanning not enabled on repo, skipping message",
                "code.namespace": self.class.name,
                "gh.repo.id": repo_id
              )

              return
            end

            message.value[:events].take(MAX_PROCESSED_ALERT_EVENTS).each do |event|
              case event[:event]
              when :ALERT_CREATED
                Hook::Event::SecretScanningAlertEvent.queue_with_repo(
                  alert_number: event[:alert_number],
                  repo:,
                  action: :created,
                )

                GitHub.logger.info(
                  "secret_scanning_alert.created delivery queued",
                  "code.namespace": self.class.name,
                  "gh.repo.id": repo_id
                )
              when :ALERT_LOCATION_CREATED
                Hook::Event::SecretScanningAlertLocationEvent.queue_with_repo(
                  alert_number: event[:alert_number],
                  location_id: event[:location_id],
                  repo:,
                  action: :created,
                )

                GitHub.logger.info(
                  "secret_scanning_alert_location.created delivery queued",
                  "code.namespace": self.class.name,
                  "gh.repo.id": repo_id
                )
              when :ALERT_REOPENED
                Hook::Event::SecretScanningAlertEvent.queue_with_repo(
                  alert_number: event[:alert_number],
                  repo:,
                  action: :reopened,
                )

                GitHub.logger.info(
                  "secret_scanning_alert.reopened delivery queued",
                  "code.namespace": self.class.name,
                  "gh.repo.id": repo_id
                )
              when :ALERT_RESOLVED
                Hook::Event::SecretScanningAlertEvent.queue_with_repo(
                  alert_number: event[:alert_number],
                  repo:,
                  action: :resolved,
                )

                GitHub.logger.info(
                  "secret_scanning_alert.resolved delivery queued",
                  "code.namespace": self.class.name,
                  "gh.repo.id": repo_id
                )
              when :ALERT_VALIDATED
                Hook::Event::SecretScanningAlertEvent.queue_with_repo(
                  alert_number: event[:alert_number],
                  repo:,
                  action: :validated,
                )

                GitHub.logger.info(
                  "secret_scanning_alert.validated delivery queued",
                  "code.namespace": self.class.name,
                  "gh.repo.id": repo_id
                )
              when :ALERT_PUBLICLY_LEAKED
                if GitHub.flipper.feature(:secret_scanning_show_single_alert_view_related_alerts).enabled?
                  Hook::Event::SecretScanningAlertEvent.queue_with_repo(
                    alert_number: event[:alert_number],
                    repo:,
                    action: :publicly_leaked,
                  )

                  GitHub.logger.info(
                    "secret_scanning_alert.publicly_leaked delivery queued",
                    "code.namespace": self.class.name,
                    "gh.repo.id": repo_id
                  )
                end
              end
            end

            timestamp = Time.at(message.timestamp)
            duration_ms = (Time.now - timestamp).to_f * 1000
            good_request = duration_ms < 60000
            GitHub.dogstats.distribution("secret_scanning.alert_events_processor.webhook.duration", duration_ms)
            GitHub.dogstats.increment("secret_scanning.alert_events_processor.webhook.duration_threshold", tags: ["success:#{good_request}"])

            GitHub.logger.info(
              "AlertEvents message processed",
              "code.namespace": self.class.name,
              "gh.repo.id": repo_id
            )
          end
        end
      end
    end
  end
end
