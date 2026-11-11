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

          push = resolve_push_from_sha(repository, ref, sha)

          if push.nil?
            Failbot.report(
              DependabotEventError.new("push not found"),
              repository_id: repository.id,
              request_id: message.value[:request_id],
              ref: ref,
              sha: sha,
              dependabot_event_id: event_id,
            )
            return message.skip("push_not_found")
          end

          if event_id > 0
            # If we have an event_id, at least one ecosystem has been detected so we can proceed to processing
            # the changes directly.
            options = { dependabot_event_id: event_id }
            RepositoryDependencyManifestChangedJob.perform_later(push.id, repository.id, options)
          else
            # If we do not have an event_id, we haven't detected any One Pipeline ecosystems so we must fallback
            # to using the monolith's push analysis before deciding what to do.

            # NOTE: This method bypasses Repositories.domain access on purpose.
            #
            # We need to use Push#dependency_manifest_changed? which isn't available via the Repositories::Push
            # model intentionally.
            #
            # Push#dependency_manifest_changed? is something we are aiming to deprecate as part of this work by
            # shifting responsibility for change file analysis to DG services outside the monolith.
            #
            push_model = Push.find_by(id: push.id) # domain-isolation-query-violation:ignore:packages/repositories (SELECT)

            if push_model.nil?
              # This should never happen since we're reloading an object we already have.
              Failbot.report(
                DependabotEventError.new("push model not found"),
                repository_id: repository.id,
                request_id: message.value[:request_id],
                push_id: push.id,
                ref: ref,
                sha: sha,
                dependabot_event_id: event_id,
              )
              return message.skip("push_model_not_found")
            end

            if push_model.initial_commit? || push_model.dependency_manifest_changed?
              RepositoryDependencyManifestChangedJob.perform_later(push.id, repository.id)
            else
              message.skip("no_legacy_manifest_changes")
            end
          end
        end

        sig { params(repository: Repositories::IRepository).returns(T::Boolean) }
        def dependabot_snapshot_readiness_enabled?(repository)
          ::DependencyGraph.dependabot_snapshot_readiness_enabled?(repository)
        end

        sig do
          params(
            repository: Repositories::IRepository,
            ref: String,
            sha: String,
          ).returns(T.nilable(Repositories::Push))
        end
        def resolve_push_from_sha(repository, ref, sha)
          return nil if sha.blank? || ref.blank?

          # This lookup is sufficient for our purposes, it will get the newest
          # push id for the `after` commit_oid we've processed.
          #
          # Most of the time, this will be 1:1 but rarely the same `after` can
          # be force pushed. Taking the newest is the safest mapping.
          Repositories.domain.pushes.latest_by_after_and_ref(
            repository_id: T.must(repository.id),
            ref: ref,
            after: sha,
          )
        end
      end
    end
  end
end
