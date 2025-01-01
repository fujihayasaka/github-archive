# typed: true
# frozen_string_literal: true

require "audit/context"
require "github/job_stats"
require "active_job/queue_adapters/job_router"
require "active_job/enqueue_failed_error"

module ActiveJob
  module QueueAdapters
    # An ActiveJob adapter that publishes jobs to aqueduct.
    #
    # If the first enqueue fails (for example, if the aqueduct circuit breaker is open), the adapter
    # will retry against a prioritized list of alternative failover paths. If none of the failover
    # paths succeeds, the adapter throws an exception.
    class AqueductAdapter
      extend T::Sig
      # Public: Publish a job to the preferred path (usually aqueduct) or fall back to a failover
      # path (e.g. a second aqueduct cluster or hydro).
      def enqueue(job)
        GitHub::JobStats.track_enqueue_time do
          route = JobRouter.route_for(job)
          result = enqueue_via_route(job, route: route)

          begin
            raise result.error unless result.ok?
          rescue result.error.class
            raise EnqueueFailedError.new("Failed to enqueue #{job.class}")
          end
        end
      end

      def enqueue_all(jobs)
        result = GitHub::Aqueduct::Job.enqueue_active_jobs(jobs.map { |job| { job: job } })

        if result.ok?
          result.value!.each do |job_result|
            job = jobs[job_result[:index]]

            error = job_result[:error]
            if error.blank?
              job.successfully_enqueued = true
              job.provider_job_id = job_result[:job_id]
            else
              job.successfully_enqueued = false
              job.enqueue_error = error
            end
          end
        else
          jobs.each do |job|
            job.successfully_enqueued = false
            job.enqueue_error = result.error
          end
        end

        jobs.count(&:successfully_enqueued?)
      end

      sig { params(job: ApplicationJob, timestamp: T.any(DateTime, Time, ActiveSupport::TimeWithZone, Numeric)).void }
      def enqueue_at(job, timestamp)
        if timestamp.to_i > (Time.now.utc + GitHub::Aqueduct::MAX_DELIVERY_TIMESTAMP_FUTURE_DURATION).to_i
          GitHub.dogstats.increment("aqueduct_adapter.timestamp_too_high", tags: job.all_stats_tags)
          IntermediaryScheduledAqueductJob.
            set(wait: GitHub::Aqueduct::MAX_DELIVERY_TIMESTAMP_FUTURE_DURATION).
            perform_later(job.serialize.to_json, Time.at(timestamp))

          return
        end

        tags = job.all_stats_tags

        # Delivery times should not be in the past
        if timestamp.to_i < Time.now.to_i
          GitHub.dogstats.increment("aqueduct_adapter.timestamp_too_low", tags: tags)
          timestamp = Time.now
        end

        # Ensure that `job#scheduled_at` is updated with the timestamp
        job.set(wait_until: Time.at(timestamp))

        GitHub.dogstats.increment("aqueduct_adapter.scheduled", tags: tags)

        route = JobRouter.route_for_scheduled_job(job)
        result = enqueue_via_route(job, route: route, deliver_at: timestamp)

        if !result.ok?
          tags = tags + ["error:#{result.error.class}"]
          GitHub.dogstats.increment("aqueduct_adapter.schedule_error", tags: tags)
        end

        result
      end

      # Public: Inspect jobs that have been enqueued.
      #
      # Returns an Array of ActiveJob instances.
      def peek(queue:, limit: 1)
        jobs = GitHub::Aqueduct::Job.peek_jobs(queue: queue, limit: limit)

        jobs.each { |job| job.send(:deserialize_arguments_if_needed) }
      end

      # Public: Inspect jobs that are currently being processed.
      #
      # Returns an Array of ActiveJob instances.
      def in_progress(queue:)
        jobs = GitHub::Aqueduct::Job.in_progress_jobs(queue: queue)

        jobs.each { |job| job.send(:deserialize_arguments_if_needed) }
      end

      # Public: Query the number of enqueued jobs for a queue.
      #
      # Returns an Integer.
      def queue_depth(queue:)
        GitHub::Aqueduct::Job.queue_depth(queue: queue)
      end

      private

      # Internal: Attempt to enqueue a job via a route. If the first path in the route fails,
      # retries via the failover paths.
      #
      # Returns a GitHub::Result.
      def enqueue_via_route(job, route:, deliver_at: nil, headers: nil)
        metadata = build_metadata
        metadata[:deliver_at] = deliver_at.to_i if deliver_at

        enqueue_args = { metadata: metadata, deliver_at: deliver_at, headers: headers }

        # Attempt to enqueue the job via the preferred path.
        result = enqueue_via(job, path: route.preferred_path, **enqueue_args)

        if result.ok?
          # If the preferred path succeeds, try the fanout paths (if any).
          route.fanout_paths.each do |fanout_path|
            fanout_result = enqueue_via(job, path: fanout_path, **enqueue_args)
            record_path_failure(job, fanout_path, fanout_result) unless fanout_result.ok?
          end
        else
          # If the preferred path fails, try the failover paths.
          record_path_failure(job, route.preferred_path, result)

          route.failover_paths.each do |failover_path|
            result = enqueue_via(job, path: failover_path, **enqueue_args)
            result.ok? ? break : record_path_failure(job, failover_path, result)
          end
        end

        result
      end

      # Internal: Attempt to enqueue a job via a specific path.
      #
      # Returns a GitHub::Result.
      def enqueue_via(job, path:, metadata:, deliver_at: nil, headers: nil)
        job.enqueue_backend = path

        enqueue_args = { metadata: metadata, deliver_at: deliver_at, headers: headers }

        GitHub::JobStats.track_enqueue_time_by_backend(backend: path) do
          case path
          when JobRouter::AQUEDUCT_GATEWAY_PATH
            enqueue_to_aqueduct(job, client: GitHub.aqueduct_gateway, **enqueue_args)
          when JobRouter::AQUEDUCT_PRIMARY_PATH
            enqueue_to_aqueduct(job, client: GitHub.aqueduct_primary, **enqueue_args)
          when JobRouter::AQUEDUCT_SECONDARY_PATH
            enqueue_to_aqueduct(job, client: GitHub.aqueduct_secondary, **enqueue_args)
          when JobRouter::HYDRO_SYNC_PATH
            enqueue_to_hydro(job, GitHub.sync_hydro_publisher, **enqueue_args)
          when JobRouter::HYDRO_ASYNC_PATH
            enqueue_to_hydro(job, GitHub.hydro_publisher, **enqueue_args)
          else
            raise ArgumentError.new("Invalid enqueue path: #{path}")
          end
        end
      end

      # Internal: Record the fact that a path failed.
      #
      # Returns nothing.
      def record_path_failure(job, path, result)
        tags = [
          "class:#{job.class.name.underscore}",
          "queue:#{job.queue_name}",
          "path:#{path}",
          "error:#{result.error.class}"
        ]
        GitHub.dogstats.increment("aqueduct_adapter.path_failure", tags: tags)
      end

      # Internal: Enqueue a job via aqueduct.
      #
      # Returns a GitHub::Result.
      def enqueue_to_aqueduct(job, metadata:, client:, deliver_at: nil, headers: nil)
        GitHub::Aqueduct::Job.enqueue_active_job(job,
          metadata: metadata,
          client: client,
          deliver_at: deliver_at,
          headers: headers,
        )
      end

      # Internal: Enqueue a job via hydro.
      #
      # Returns a GitHub::Result.
      def enqueue_to_hydro(job, publisher, metadata:, deliver_at: nil, headers: nil)
        topic = GitHub.dynamic_lab? ? "review-lab.v1.AqueductJob" : "github.v1.AqueductJob"

        begin
          result = publisher.publish(
            {
              serialized: GitHub::JSON.encode(job.serialize),
              metadata: GitHub::JSON.encode(metadata),
              current_ref: GitHub.current_ref,
              deliver_at: deliver_at,
              headers: headers,
            },
            schema: "github.v1.AqueductJob",
            topic: topic,
            # Publish to a single partition to avoid creating more kafka connections that necessary
            # per process.
            partition_key: Process.pid.to_s,
            topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }, # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
          )
        rescue => e # rubocop:todo Lint/GenericRescue
          return GitHub::Result.error(e)
        end

        result.success? ? GitHub::Result.new : GitHub::Result.error(result.error)
      end

      # Internal: Build a Hash of contextual info to be serialized with the job payload.
      def build_metadata
        {
          queued_at: Time.now.to_f,
          context: expand_context_payload(GitHub.context.to_hash),
          audit_context: Audit.context.to_hash
        }
      end

      def expand_context_payload(payload)
        payload[:created_at] ||= Time.now
        payload[:created_at] = (payload[:created_at].utc.to_f * 1000).round unless payload[:created_at].is_a?(Integer)

        if actor_ip = payload[:actor_ip]
          GitHub.dogstats.distribution_time "audit", tags: ["action:ip_lookup"] do
            location = GitHub::Location.look_up(actor_ip)
            location[:location] = {
              lat: location.delete(:latitude).to_f,
              lon: location.delete(:longitude).to_f,
            }

            payload[:actor_location] = location
          end
        end

        # Spokes Access API's push state is stored in GitHub.context, but is a
        # transient value and should not be propagated to background jobs.
        payload.delete(:spokesapi_push_state)

        payload
      end

      def redis
        @redis ||= Redis::Namespace.new(:resque, redis: GitHub.job_coordination_redis)
      end
    end
  end
end
