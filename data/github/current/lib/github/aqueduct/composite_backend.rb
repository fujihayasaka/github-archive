# typed: false
# frozen_string_literal: true

require "forwardable"

module GitHub
  module Aqueduct
    class CompositeBackend
      attr_reader :primary, :secondary, :gateway, :backend

      # Delegate all methods except pop to @backend
      extend Forwardable
      def_delegators :@backend, *(::Aqueduct::Worker::Backend.instance_methods(false) - [:pop])

      # These names must match the backend names in the aqueduct-gateway deployment for correct utilization metrics
      PRIMARY_BACKEND_NAME = "aqueduct_primary"
      SECONDARY_BACKEND_NAME = "aqueduct_secondary"
      GATEWAY_BACKEND_NAME = "aqueduct_gateway"

      # Queries for the pids of all peer worker processes.
      def self.worker_pids
        Progeny::Command.new("ps", "--ppid", Process.ppid.to_s, "-o", "pid", "--no-headers").out.lines.map(&:to_i)
      end

      # primary, secondary, and gateway are all instances of Aqueduct::Worker::AqueductBackend
      def initialize(primary:, secondary:, gateway:, actor: nil, prioritize_by: nil)
        @backend = @primary = primary
        @secondary = secondary
        @gateway = gateway
        @actor = actor || Actor.new

        @prioritize_by = prioritize_by

        # Queue configs without a scheduling hint will be assigned a low priority.
        @prioritized_queues ||= {}

        # Set of prioritized queues with a high priority value if scheduling hints are not configured.
        # This is a temporal attribute. It will be removed after default low prioritization is enabled for all queues.
        @prioritized_queues_with_high_priority_default ||= {}

        @backends_by_name = Hash[
          PRIMARY_BACKEND_NAME => @primary,
          SECONDARY_BACKEND_NAME => @secondary,
          GATEWAY_BACKEND_NAME => @gateway
        ]

        # The mutex and backend_name field can be refactored into aqueduct-client-ruby after dotcom worker machinery
        # (i.e. worker adapter, status_server) is refactored into a library
        @mutex = Mutex.new
        @backend_name = ""
        @base_tags = GitHub.aqueduct_tags
        @tags = @base_tags
      end

      # We check the backend at the pop level so each worker process works a single job with a
      # specific backend. This is due to single process always making calls to the backend
      # in a specific order: pop, heartbeat, report_success/report_failure. And only ever working 1
      # job at a time.
      def pop(queues, timeout, tags: {}, worker_id:, worker_pool: nil, worker_idle_ms: 0)
        tags ||= {}
        new_tags = @base_tags.merge(tags)
        if @backend == @gateway
          if @prefer_secondary
            new_tags["preferred_backend"] = SECONDARY_BACKEND_NAME
          end
        end
        set_tags(new_tags)

        # Determine the order in which queues are popped
        # By default, we rely on resqued shuffling, but we can use custom queue sorting
        # as well if the feature flag is enabled.
        new_tags["queue_ordering"] = "resqued_shuffle"
        if @prioritize_by && prioritize_queues?

          # When a queue config doesn't have a scheduling hint, we want to assign it a low priority.
          # If there is an incident, we want queue delays caused only by explicit high priority queues and not queues misconfigured
          queues = (@prioritized_queues[queues] ||= @prioritize_by.sort(queues))
          new_tags["queue_ordering"] = "prioritized"
        end

        job = @backend.pop(queues, timeout, tags: new_tags, worker_id: worker_id, worker_pool: worker_pool, worker_idle_ms: worker_idle_ms)

        # We report pop stats mostly for tracking queue ordering prioritization across worker pools
        GitHub.dogstats.count("job.backend.pop", 1, tags: new_tags)

        job
      end

      def prioritize_queues?
        GitHub.flipper["prioritize_resqued_queues_#{GitHub.role}"].enabled?
      end

      # Use the gateway in place of the primary or secondary, this takes precedence over both.
      def use_gateway?
        GitHub.flipper["use_gateway_aqueduct_backend"].enabled?(@actor)
      end

      # Visible for testing.
      def use_secondary?
        # Some app-roles aren't well-suited to actor-based feature flagging and require a full-time
        # dedicated secondary worker.
        if GitHub.at_least_one_aqueduct_secondary_worker?
          return true if self.class.worker_pids.max == Process.pid
        end

        GitHub.flipper["use_secondary_aqueduct_backend"].enabled?(@actor)
      end

      # Called by before_pop callback to decide which backend to use to retrieve messages.
      def maybe_switch_backends
        @prefer_secondary = false
        case
        when use_gateway?
          @backend = @gateway
          @prefer_secondary = use_secondary?
          update_backend_name_for_metrics(GATEWAY_BACKEND_NAME)
        when use_secondary?
          @backend = @secondary
          update_backend_name_for_metrics(SECONDARY_BACKEND_NAME)
        else
          @backend = @primary
          update_backend_name_for_metrics(PRIMARY_BACKEND_NAME)
        end
      end

      # Allow other non-worker threads (i.e. status_server) to safely obtain the backend name
      # and worker metrics to scrape the correct backend name from the worker's procline
      def update_backend_name_for_metrics(name)
        set_backend_name(name)
        GitHub::JobStats.record_backend_name(name)
      end

      def backend_status
        name = backend_name
        if @backends_by_name.has_key? name
          backend_url = @backends_by_name[name].url
        else
          backend_url = "unknown"
        end

        {
          backend: name,
          backend_url: backend_url,
          tags: get_tags
        }
      end

      def backend_name
        @mutex.synchronize do
          @backend_name
        end
      end

      def set_backend_name(backend_name)
        @mutex.synchronize do
          @backend_name = backend_name
        end
      end

      def get_tags
        @mutex.synchronize do
          @tags
        end
      end

      # Store the tags in an instance variable so that the status_server can obtain the worker's current tags for
      # worker utilization reporting purposes
      def set_tags(tags)
        @mutex.synchronize do
          @tags = tags
        end
      end

      # Which backend is controlled at the processes level instead of the role or a global level,
      # this gives us fine grain control of the rollout and means that if a single aqueduct is
      # struggling to respond to requests then we have entire workers that are out of struggling
      # instead of all the workers struggling due to some % of the calls being backed up.
      # Example: if we set a 50/50 split and the primary aqueduct is slowing down then 50%
      # of the workers are now subjected to that perf issue and the other 50% chug along.
      # As opposed to if we did it on the global level 50% of calls for all the workers now
      # slow down which would eventually lead to all workers going slow.
      #
      # The actor identifier includes the current minute to ensure a
      # semi-frequent "re-roll" ensure any accidental imbalances can be evened
      # out over time.
      class Actor
        include GitHub::FlipperActor
        include GitHub::VexiActor

        DELIMITER = "+"

        def self.find_by_id(id)  # rubocop:disable GitHub/FindByDef
          id_parts = id.split(DELIMITER)
          # current minute is calculated as used, and ignored when finding an actor
          if id_parts.size == 2 || id_parts.size == 3
            new(hostname: id_parts[0], pid: id_parts[1])
          end
        end

        def initialize(hostname: Socket.gethostname, pid: Process.pid)
          @hostname = hostname
          @pid = pid
        end

        def id
          minute ||= Time.now.to_i / 60
          [@hostname, @pid, minute].join(DELIMITER)
        end

        def to_s
          id
        end

        def ==(other)
          self.class == other.class && id == other.id
        end
      end
    end
  end
end
