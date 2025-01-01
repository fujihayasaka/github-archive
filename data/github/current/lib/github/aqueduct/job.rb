# typed: false
# frozen_string_literal: true

# GitHub::Aqueduct::Job handles enqueuing and executing jobs via aqueduct.
#
# It provides the top-level execution context for attaching execution/enqueue
# hook behaviors, and delegates to subclasses for execution.
module GitHub
  module Aqueduct
    class Job
      # Consider the enqueue a failure if it completed successfully but took longer
      # than 1 second.
      MAX_ENQUEUE_DURATION = 2.seconds

      # Aqueduct can only handle payloads up to 5 MB
      MAX_PAYLOAD_SIZE = 5.megabytes

      # Upper bound for payloads that are stored in redis because they can't fit in aqueduct:
      MAX_EXTERNAL_PAYLOAD_SIZE = 25.megabytes

      # Error message text if Aqueduct rejects because Kafka serialized payload exceeds MAX_PAYLOAD_SIZE
      AQUEDUCT_PAYLOAD_TOO_LARGE_ERROR = "AQUEDUCT_PAYLOAD_TOO_LARGE"

      TIMING_THRESHOLDS = [35, 100, 1000]

      # Heartbeat more frequently than the default of 60 seconds so that we can reduce the
      # redelivery timeout.
      HEARTBEAT_INTERVAL = 15.seconds

      # Default to 3x the heartbeat interval to allow for failed or delayed heartbeats.
      DEFAULT_REDELIVERY_TIMEOUT = HEARTBEAT_INTERVAL * 3

      NOOP_HEADER = "noop"

      FS_QUEUE_REGEX = /_(fs\d+|github-d?fs\d+-cp\d-prd|github-dfs-[0-9a-f]{7})$/

      include ActiveSupport::Callbacks
      define_callbacks :execute

      def self.before_execute(*args, &block)
        set_callback :execute, :before, *args, &block
      end

      def self.after_execute(*args, &block)
        set_callback :execute, :after, *args, &block
      end

      def self.around_execute(*args, &block)
        set_callback :execute, :around, *args, &block
      end

      # In review-lab we want to provide isolation between review-lab deployments.
      # Historically this was done by prefixing the queue name with the lab name
      # (i.e.  `<review-lab-name>_<queue-name>`). This queue prefixing scheme leads
      # to high queue cardinality.
      #
      # Aqueduct restricts the number of queues per application, so high queue
      # cardinality is a problem. To reduce queue cardinality, we override
      # queue names in review-lab to a single queue composed of the review-lab
      # name (i.e. `review-lab-<review-lab-name>`. When aqueduct workers start
      # up, they filter each assigned queue through
      # `AqueductAdapter#aqueduct_queue_name` to ensure that publishers and
      # workers are both aware of the naming scheme.
      def self.aqueduct_queue_name(queue_name)
        if GitHub.dynamic_lab?
          "review-lab-#{GitHub.dynamic_lab_name.parameterize}"
        else
          queue_name
        end
      end

      def self.timer
        @timer ||= Timer.new
      end

      def self.max_payload_size
        MAX_PAYLOAD_SIZE
      end

      def self.max_external_payload_size
        MAX_EXTERNAL_PAYLOAD_SIZE
      end

      # Internal: the calculated queue name for this job.
      def self.queue_name(queue)
        if GitHub.dynamic_lab?
          "review-lab-#{GitHub.dynamic_lab_name.parameterize}"
        elsif queue.to_s.match(FS_QUEUE_REGEX)
          # File server maintenance jobs can only run on the file servers. File
          # server workers dynamically generate queue names that are derived from
          # the host name to ensure that jobs are routed to the correct server
          # e.g. github-dfs-0bccb85.cp1-iad.github.net works the "maint_github-dfs-0bccb85"
          # queue. We don't allow "lab_" prefixing of file server queues because
          # no workers would work those queues. As a result, file server jobs
          # enqueued in lab are executed on the real file servers.
          queue
        else
          # `GitHub.background_job_queue_prefix` is used to namespace queues in the
          # staff-only lab environment.
          "#{GitHub.background_job_queue_prefix}#{queue}"
        end
      end

      # Public: Enqueue an ActiveJob job.
      #
      # Returns a GitHub::Result indicating enqueue success or failure.
      def self.enqueue_active_job(job, metadata: {}, client: GitHub.aqueduct_primary, deliver_at: nil, headers: nil)
        if !client.circuit_breaker.allow_request?
          return GitHub::Result.error(UnavailableError.new)
        end

        result = nil # establish variable scope
        duration = timer.time do
          begin
            enqueue(job, deliver_at: deliver_at, headers: headers, metadata: metadata, client: client)
            result = GitHub::Result.new
          rescue => e # rubocop:todo Lint/GenericRescue
            correlation_id = SecureRandom.urlsafe_base64(18)
            GitHub.logger.error({ :exception => e, "gh.correlation_id" => correlation_id, "gh.job.queue" => queue_name(job.queue_name), "gh.job.name" => job.class.name })

            if e.is_a?(::Aqueduct::Client::ClientError)
              Failbot.report(e, {
                app: "github-aqueduct",
                queue: queue_name(job.queue_name),
                job: job.class,
                splunk_correlation_id: correlation_id,
              }.merge(e.metadata.map { |k, v| ["aqueduct_#{k}", v] }.to_h))
            else
              Failbot.report(e, {
                app: "github-aqueduct",
                queue: queue_name(job.queue_name),
                job: job.class,
                splunk_correlation_id: correlation_id,
              })
            end
            result = GitHub::Result.error(e)
          end
        end

        handle_result(result: result, duration: duration, queue: queue_name(job.queue_name), job_class: job.class, client: client)
      end

      def self.enqueue_active_jobs(batch, client: GitHub.aqueduct_primary)
        if !client.circuit_breaker.allow_request?
          return GitHub::Result.error(UnavailableError.new)
        end

        result = nil
        duration = timer.time do
          begin
            response = enqueue_batch(batch: batch, client: client)
            result = GitHub::Result.new { response }
          rescue => e # rubocop:todo Lint/GenericRescue
            correlation_id = SecureRandom.urlsafe_base64(18)
            batch.each do |b|
              job = b[:job]
              GitHub.logger.error({ :exception => e, "gh.correlation_id" => correlation_id, "gh.job.queue" => queue_name(job.queue_name), "gh.job.name" => job.class.name })
              if e.is_a?(::Aqueduct::Client::ClientError)
                Failbot.report(e, {
                  app: "github-aqueduct",
                  queue: queue_name(job.queue_name),
                  job: job.class,
                  splunk_correlation_id: correlation_id,
                }.merge(e.metadata.map { |k, v| ["aqueduct_#{k}", v] }.to_h))
              else
                Failbot.report(e, {
                  app: "github-aqueduct",
                  queue: queue_name(job.queue_name),
                  job: job.class,
                  splunk_correlation_id: correlation_id,
                })
              end
              result = GitHub::Result.error(e)
            end
          end
        end
        handle_batch_result(result: result, duration: duration, batch: batch, client: client)
      end

      # Enqueue a protobuf envelope to aqueduct
      #
      # payload - the protobuf bytes of a Hydro envelope.
      def self.enqueue_hydro_message_job(payload, queue:, headers:, deliver_at: nil, client: GitHub.aqueduct_primary)
        if !client.circuit_breaker.allow_request?
          return GitHub::Result.error(UnavailableError.new)
        end

        result = nil # establish variable scope
        duration = timer.time do
          begin
            tags = ["queue:#{queue}"]
            GitHub.dogstats.distribution_time("rpc.aqueduct.enqueue.time", tags: tags) do
              GitHub.dogstats.distribution_time("rpc.aqueduct.time", tags: ["rpc_operation:send_job"]) do
                client.send_job(
                  queue: queue,
                  payload: payload,
                  headers: headers,
                  redelivery_timeout_secs: DEFAULT_REDELIVERY_TIMEOUT.to_i,
                  deliver_at: deliver_at&.to_i,
                )
              end
            end

            result = GitHub::Result.new
          rescue => e # rubocop:todo Lint/GenericRescue
            correlation_id = SecureRandom.urlsafe_base64(18)
            GitHub.logger.error({ :exception => e, "gh.correlation_id" => correlation_id, "gh.job.queue" => queue })
            if e.is_a?(::Aqueduct::Client::ClientError)
              Failbot.report(e, {
                app: "github-aqueduct",
                queue: queue,
                splunk_correlation_id: correlation_id,
              }.merge(e.metadata.map { |k, v| ["aqueduct_#{k}", v] }.to_h))
            else
              Failbot.report(e, {
                app: "github-aqueduct",
                queue: queue,
                splunk_correlation_id: correlation_id,
              })
            end
            result = GitHub::Result.error(e)
          end
        end

        handle_result(result: result, duration: duration, queue: queue, client: client)
      end

      # Public: Reset the time budgeting stats at the end of the request.
      def self.reset_stats
        Thread.current[:aqueduct_time_budget] = 0
      end

      def self.handle_result(result:, duration:, queue:, job_class: nil, client:)
        tags = ["queue:#{queue}"]
        tags << "class:#{job_class}" if job_class

        Thread.current[:aqueduct_time_budget] ||= 0
        Thread.current[:aqueduct_time_budget] += duration

        if result && result.ok?
          report_threshold(duration * 1000)
          if duration < MAX_ENQUEUE_DURATION
            client.circuit_breaker.success
          else
            GitHub.dogstats.increment("rpc.aqueduct.too_slow", tags: tags)
            client.circuit_breaker.failure
          end

          return result
        end

        # Oversized payload errors are thrown before we attempt to send
        # aqueduct API calls, so they don't count for or against the circuit
        # breaker.
        if result.error.is_a?(PayloadTooLargeError)
          GitHub.dogstats.increment("rpc.aqueduct.oversized_payload", tags: tags)
        else
          client.circuit_breaker.failure
        end

        result
      end

      def self.handle_batch_result(result:, duration:, batch:, client:)
        tags = ["batch_size:#{batch.size}"]
        Thread.current[:aqueduct_time_budget] ||= 0
        Thread.current[:aqueduct_time_budget] += duration

        if result && result.ok?
          report_threshold(duration * 1000)
          if duration < MAX_ENQUEUE_DURATION
            client.circuit_breaker.success
          else
            GitHub.dogstats.increment("rpc.aqueduct.too_slow", tags: tags)
            client.circuit_breaker.failure
          end
          return result
        end

        # Oversized payload errors are thrown before we attempt to send
        # aqueduct API calls, so they don't count for or against the circuit
        # breaker.
        if result.error.is_a?(PayloadTooLargeError)
          GitHub.dogstats.increment("rpc.aqueduct.oversized_payload", tags: tags)
        else
          client.circuit_breaker.failure
        end

        result
      end

      # Public: Processes an Aqueduct::Worker::Job. Deserializes and executes
      # the job contained in the payload. Called by resqued's handler.
      #
      # job - an ::Aqueduct::Worker::Job
      # status - an ::Aqueduct::Worker::JobStatus, for recording success/failure
      def self.execute(job, status)
        if job.headers["hydro-encoding"]
          HydroMessageJobContext.new(job).execute(status)
        else
          ActiveJobContext.new(job).execute(status)
        end
      end

      def self.report_threshold(duration_ms)
        TIMING_THRESHOLDS.each do |t|
          if duration_ms <= t
            GitHub.dogstats.increment("rpc.aqueduct.enqueue.time.threshold", tags: ["le:#{t}", "rpc_operation:send_job"])
          end
        end
      end

      # Public: Inspect jobs that have been enqueued.
      #
      # Returns an Array of ActiveJob instances.
      def self.peek_jobs(queue:, limit:, client: GitHub.aqueduct_primary)
        client.peek_jobs(queue: queue, count: limit)[:payloads].map do |encoded|
          decoded = GitHub::JSON.decode(encoded)
          ActiveJob::Base.deserialize(decoded.fetch("payload"))
        end
      rescue ::Aqueduct::Client::ClientError => e
        Failbot.report(e, { app: "github-aqueduct" })
        []
      end

      # Public: Inspect jobs that are currently being processed.
      #
      # Returns an Array of ActiveJob instances.
      def self.in_progress_jobs(queue:, client: GitHub.aqueduct_primary)
        client.in_progress_jobs(queue: queue).fetch(:in_progress).each_with_object([]) do |job, memo|
          next if job[:payload].blank? # some jobs do not have payloads
          decoded = GitHub::JSON.decode(job[:payload])
          memo << ActiveJob::Base.deserialize(decoded.fetch("payload"))
        end
      rescue ::Aqueduct::Client::ClientError => e
        Failbot.report(e, { app: "github-aqueduct" })
        []
      end

      # Public: List queues for this app
      #
      # Returns an Array of queue names
      def self.list_queues(client: GitHub.aqueduct_primary)
        client.list_queues[:queues].map { |q| q[:name] }
      rescue ::Aqueduct::Client::ClientError => e
        Failbot.report(e, { app: "github-aqueduct" })
        []
      end

      # Public: Query the number of enqueued jobs for a queue.
      #
      # Returns an Integer.
      def self.queue_depth(queue:, client: GitHub.aqueduct_primary)
        client.queue_depth(queue: queue)[:depth]
      rescue ::Aqueduct::Client::ClientError => e
        Failbot.report(e, { app: "github-aqueduct" })
        0
      end

      # The Aqueduct::Worker::Job instance
      attr_reader :job

      # The class name of the job.
      attr_reader :job_class

      # The queue this job is from
      attr_reader :queue

      # The job ID assigned by aqueduct for tracking the job within aqueduct.
      # Note that this ID is separate from the ActiveJob ID.
      attr_reader :aqueduct_job_id

      # Initialize a Job execution context with an Aqueduct::Worker::Job instance.
      def initialize(job)
        @job = job
        @aqueduct_job_id = job.id
      end

      # Internal: execute the job.
      def execute_job(status)
        raise NotImplementedError
      end

      # Public: enqueue an activejob job to aqueduct.
      def self.enqueue(job, deliver_at: nil, headers: nil, metadata: {}, client: GitHub.aqueduct_primary)
        queue = queue_name(job.queue_name)
        job_class = job.class.name
        serialized = job.serialize

        tags = ["queue:#{queue}", "class:#{job_class}"]
        GitHub.dogstats.distribution_time("rpc.aqueduct.enqueue.time", tags: tags) do
          payload = GitHub.dogstats.distribution_time("rpc.aqueduct.job_encode.time") do
            payload_hash = {
              queue: queue,
              job_class: job_class,
              payload: serialized,
              metadata: metadata,
            }
            # Warn to Failbot if we're trying to encode a payload with invalid UTF8
            GitHub::JSON.encode(payload_hash, warn_utf8: true)
          end

          pointer = false
          pointer_payload_size = 0
          if payload.bytesize >= max_payload_size && payload.bytesize <= max_external_payload_size
            pointer = true
            payload_hash = {
              queue: queue,
              job_class: job_class,
              pointer: PayloadPointer.create(serialized, queue: queue),
              metadata: metadata,
            }
            pointer_payload_size = payload.bytesize
            payload = GitHub::JSON.encode(payload_hash)
          end

          # see if it's still too large: either the payload pointer failed, or it was too large entirely:
          if payload.bytesize >= max_payload_size
            raise PayloadTooLargeError.new("Payload for #{job_class} was #{payload.bytesize} bytes")
          end

          GitHub.dogstats.increment("rpc.aqueduct.pointer_payload", tags: tags) if pointer
          GitHub.dogstats.distribution("rpc.aqueduct.payload_size", payload.bytesize, tags: tags)
          GitHub.dogstats.distribution("rpc.aqueduct.pointer_payload_size", pointer_payload_size, tags: tags) if pointer_payload_size > 0

          GitHub.dogstats.distribution_time("rpc.aqueduct.time", tags: ["rpc_operation:send_job"]) do
            begin
              client.send_job(
                queue: queue,
                payload: payload,
                headers: headers,
                redelivery_timeout_secs: (job.redelivery_timeout || DEFAULT_REDELIVERY_TIMEOUT).to_i,
                max_redelivery_attempts: job.max_redelivery_attempts&.to_i,
                deliver_at: deliver_at&.to_i,
                external_id: job.job_id,
                ttl: job.ttl&.to_i,
              )
            rescue ::Aqueduct::Client::RequestError => e
              if e.error.msg.include?(AQUEDUCT_PAYLOAD_TOO_LARGE_ERROR)
                raise PayloadTooLargeError.new("Payload for #{job_class} was #{payload.bytesize} bytes. #{e.error.msg}")
              else
                raise e
              end
            end
          end
        end
      end

      # Public: enqueue a batch of active jobs to aqueduct
      #
      # batch - an array of hash of jobs and options to enqueue.
      def self.enqueue_batch(batch:, client: GitHub.aqueduct_primary)
        batch_items = []
        send_request_index = 0
        index_mapping = {}
        responses = []
        batch.each_with_index do |b, index|
          job = b[:job]
          options = b[:options] || {}
          queue = queue_name(job.queue_name)
          job_class = job.class.name
          serialized = job.serialize
          payload_hash = {
            queue: queue,
            job_class: job_class,
            payload: serialized,
            metadata: options.fetch(:metadata, {}),
          }
          # Warn to Failbot if we're trying to encode a payload with invalid UTF8
          payload = GitHub::JSON.encode(payload_hash, warn_utf8: true)

          pointer = false
          if payload.bytesize >= max_payload_size && payload.bytesize <= max_external_payload_size
            pointer = true
            payload_hash = {
              queue: queue,
              job_class: job_class,
              pointer: PayloadPointer.create(serialized, queue: queue),
              metadata: options.fetch(:metadata, {}),
            }
            payload = GitHub::JSON.encode(payload_hash)
          end

          # see if it's still too large: either the payload pointer failed, or it was too large entirely
          if payload.bytesize >= max_payload_size
            Failbot.report(PayloadTooLargeError.new("Payload for #{job_class} was #{payload.bytesize} bytes"), {
              app: "github-aqueduct",
              queue: queue,
              job: job_class,
            })
            next
          end

          batch_item = { queue: queue,
            payload: payload,
            headers: options[:headers],
            redelivery_timeout_secs: (job.redelivery_timeout || DEFAULT_REDELIVERY_TIMEOUT).to_i,
            max_redelivery_attempts: job.max_redelivery_attempts&.to_i,
            deliver_at: options[:deliver_at]&.to_i
          }
          batch_items << batch_item
          index_mapping[send_request_index] = index
          send_request_index += 1
        end

        GitHub.dogstats.distribution_time("rpc.aqueduct.time", tags: ["rpc_operation:send_batch_jobs"]) do
          begin
            response = client.send_jobs(batch_items)
            response[:batch_message_responses].each do |r|
              responses << { index: index_mapping[r[:index]], job_id: r[:job_id], error: r[:error] }
            end
            responses
          rescue ::Aqueduct::Client::RequestError => e
            if e.error.msg.include?(AQUEDUCT_PAYLOAD_TOO_LARGE_ERROR)
              raise PayloadTooLargeError.new("Payload for #{job_class} was #{payload.bytesize} bytes. #{e.error.msg}")
            else
              raise e
            end
          end
        end
      end

      # Public: execute the job. The aqueduct client will ACK the job as long as this handler doesn't
      # throw an exception. If the client does not ACK the job, it will be redelivered by aqueduct.
      # There are several ACK-ing scenarios to consider:
      # - before_execute hook failure - raise the exception to ensure the job is not ACK'd
      # - job success - no action required, the lack of an exception will trigger an automatic ACK
      # - job failure - swallow the exception to ensure an ACK, but set status as failed
      # - after_execute hook failure - swallow the exception to ensure an ACK without changing status
      def execute(status)
        # If the job is a no-op job, don't execute job hooks and don't execute the job.
        if noop?
          tags = ["queue:#{queue}", "class:#{job_class}"]
          GitHub.dogstats.increment("aqueduct_worker.noop", tags: tags)
          GlobalInstrumenter.instrument("jobs.noop", { serialized: payload })

          return
        end

        before_hooks_finished = false
        begin
          run_callbacks :execute do
            before_hooks_finished = true
            begin
              execute_job
            rescue Exception => e # rubocop:todo Lint/GenericRescue
              Failbot.push(critical: true)
              Failbot.report(e)
              GitHub::JobStats.record_error(e)
              status.failed!
            end
          end
        rescue Exception => e # rubocop:todo Lint/GenericRescue
          GitHub::JobStats.record_error(e)

          if before_hooks_finished
            Failbot.report(e, critical: true)
          else
            raise e
          end
        end
      end

      def noop?
        @headers && @headers[NOOP_HEADER]
      end

      PayloadTooLargeError = Class.new(StandardError)

      UnavailableError = Class.new(StandardError)

      class PayloadPointer
        # Internal: Store a oversized payload and return a pointer.
        #
        # Returns a String.
        def self.create(payload, queue:)
          day = Date.today.to_s
          key = "aq:job:#{day}:#{queue}:#{SecureRandom.uuid}"
          GitHub.job_coordination_redis.set(key, GitHub::JSON.encode(payload), ex: 2.weeks.to_i)
          "redis://#{key}"
        end

        # Internal: Fetch a payload for a pointer.
        #
        # Returns a String.
        def self.fetch(pointer)
          _, key = pointer.split("://")
          GitHub::JSON.decode(GitHub.job_coordination_redis.get(key))
        end

        # Internal: Clean up a payload for a pointer.
        #
        # Returns nothing.
        def self.cleanup(pointer)
          _, key = pointer.split("://")
          GitHub.job_coordination_redis.del(key)
        end
      end

      class Timer
        def time
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        end
      end
    end
  end
end
