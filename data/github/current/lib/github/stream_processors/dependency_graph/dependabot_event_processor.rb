# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependencyGraph
      class DependabotEventProcessor < SingleMessageProcessor
        class DependabotEventError < StandardError; end

        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependency_graph-dependabot_event_processor"
        DEFAULT_SUBSCRIBE_TO = /dependency_graph\.v0\.DependabotEventProcessed\Z/

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

        # Processes an individual DependabotEventProcessed message from Hydro.
        #
        # DS-API publishes this event after it finishes processing an init or push event.
        # The processor enqueues the appropriate monolith job to continue the alerting pipeline.
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          repository_id = message.value[:repository_id]
          event_type = message.value[:event_type]
          event_id = message.value[:event_id]
          ref = message.value[:ref].to_s
          sha = message.value[:sha].to_s

          repository = Repositories.domain.by_id(repository_id)
          if repository.nil?
            Failbot.report(
              DependabotEventError.new("repository not found"),
              repository_id: repository_id,
              request_id: message.value[:request_id],
              ref: ref,
              sha: sha,
              dependabot_event_id: event_id,
            )
            return message.skip("repository_not_found")
          end
          return message.skip("feature_flag_disabled") unless dependabot_snapshot_readiness_enabled?(repository)

          case event_type
          when :EVENT_TYPE_INIT
            enqueue_init_job(repository, event_id)
          when :EVENT_TYPE_PUSH
            enqueue_push_job(message, repository, ref, sha, event_id)
          when :EVENT_TYPE_PULL_REQUEST
            # We do not scan for vulnerabilities on Pull Requests at present.
            message.skip("pull_request_event")
          else
            message.skip("unknown_event_type")
          end
        end

        private

        sig { params(repository: Repositories::IRepository, event_id: Integer).void }
        def enqueue_init_job(repository, event_id)
          options = {}
          options[:dependabot_event_id] = event_id if event_id > 0

          RepositoryDependencyManifestInitializationJob.perform_later(repository.id, options)
        end

        sig do
          params(
            message: GitHub::StreamProcessors::Message,
            repository: Repositories::IRepository,
            ref: String,
            sha: String,
            event_id: Integer,
          ).void
        end
        def enqueue_push_job(message, repository, ref, sha, event_id)
          if ref.blank? || sha.blank?
            Failbot.report(
              DependabotEventError.new("missing git coordinates"),
              repository_id: repository.id,
              request_id: message.value[:request_id],
              ref: ref,
              sha: sha,
              dependabot_event_id: event_id,
            )
            return message.skip("missing_git_coordinates")
          end

          RepositoryDependencyFindPushJob.perform_later(
            repository_id: T.must(repository.id),
            ref: ref,
            sha: sha,
            dependabot_event_id: event_id > 0 ? event_id : nil,
          )
        end

        sig { params(repository: Repositories::IRepository).returns(T::Boolean) }
        def dependabot_snapshot_readiness_enabled?(repository)
          ::DependencyGraph.dependabot_snapshot_readiness_enabled?(repository)
        end
      end
    end
  end
end
