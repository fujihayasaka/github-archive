# typed: false
# frozen_string_literal: true

require "aqueduct"
require "json"
require "net/http"
require "github/faraday_adapter/persistent_excon"
require "set"
require "socket"

module Resqued
  class WorkerMetrics
    DEFAULT_GET_PROCS = -> {
      `ps -e --no-headers -o pid,ppid,etime,cmd`.lines
    }
    DEFAULT_GET_METADATA = -> {
      return {} unless File.exist?("/etc/github/metadata.json")
      JSON.parse(File.read("/etc/github/metadata.json"))
    }

    RESQUED_LISTENER_RE = /\A\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<etime>\S+)\s+resqued-.+ listener #\d+ \S+ \[(?<sha>\S+)\] \[(?<state>\S+)\]/
    AQUEDUCT_WORKER_RE = /\A\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<etime>\S+)\s+aqueduct\S+( \[(?<sha>\w+)\] \[(?<backend>\w+)\])?.+(?<state>Processing|Waiting|Quiesced|Paused)(.*since (?<since>.\d+))?/

    ORPHANED_WORKER = "orphaned"
    LISTENER_STATES = %w[
      starting
      running
      shutdown
    ] + [ORPHANED_WORKER]

    # Jobs processing for longer than 5 hours after shutdown are considered stale
    STALE_THRESHOLD = 5 * 60 * 60

    # Listeners running for more than 5 days are presumed to be stalled.
    STALLED_LISTENER_TIMEOUT = 5 * 24 * 60 * 60

    PRIMARY_BACKEND_NAME = "aqueduct_primary"
    SECONDARY_BACKEND_NAME = "aqueduct_secondary"
    GATEWAY_BACKEND_NAME = "aqueduct_gateway"

    def initialize(get_procs: nil, get_metadata: nil, status_client: nil, shard_id_client: nil)
      @get_procs = get_procs || DEFAULT_GET_PROCS
      @get_metadata = get_metadata || DEFAULT_GET_METADATA
      @status_client = status_client || StatusClient.new
      @shard_id_client = shard_id_client || ProtobufShardIdClient.new(aqueduct_urls: [
        GitHub.aqueduct_gateway_url,
        GitHub.aqueduct_primary_url,
        GitHub.aqueduct_secondary_url])
    end

    def generate
      aqueduct_workers = parse_workers
      stats = Results.new

      metadata = @get_metadata.call
      stats.deployable = metadata.dig("attributes", "github", "deployable")

      # Specify the known backends
      aqueduct_backends = Set[PRIMARY_BACKEND_NAME, SECONDARY_BACKEND_NAME]
      # Add whatever else we see
      observed_backends = aqueduct_workers.map(&:backend).uniq.filter { |backend| backend != GATEWAY_BACKEND_NAME }
      aqueduct_backends.merge(observed_backends)

      workers_by_state_counts = {}
      # Accumulate counts for non-gateway workers
      LISTENER_STATES.each do |listener_state|
        aqueduct_backends.each do |backend|
          [true, false].each do |active|
            key = "#{listener_state}|#{backend}|#{active}"
            workers_by_state_counts[key] = CountByState.new(
              count: aqueduct_workers.count do |w|
                w.active? == active &&
                  w.listener_state == listener_state &&
                  w.backend == backend
              end,
              state: (active ? :active : :idle),
              listener_state: listener_state,
              backend: backend,
              )
          end
        end
      end

      # Resolve counts for gateway workers and add them to non-gateway counts
      gateway_workers = aqueduct_workers.filter { |w| w.backend == GATEWAY_BACKEND_NAME }
      unless gateway_workers.empty?
        gateway_url = gateway_workers.first.backend_url

        clients = []
        workers = []
        gateway_workers.each do |w|
          tags = w.tags.dup || {}
          # Allows gateway to apply rule overrides to determine the backend
          tags["publishing_app"] = w.publishing_app || ""
          clients.push({ client_id: w.client_id, tags: tags })
          workers.push({ id: w.worker_id, tags: tags })
        end

        gateway_resp = @shard_id_client.get(url: gateway_url, clients: clients, workers: workers)
        unless gateway_resp.nil?
          backend_names = gateway_resp[:backend_names] || {}
          backend_shards = gateway_resp[:backend_ids] || {}
          LISTENER_STATES.each do |listener_state|
            [true, false].each do |active|
              gateway_workers.each do |w|
                # Prefer client_id to support server-side cutover to worker_id when client_id omitted
                backend = backend_names.dig(w.client_id, :value)
                if backend.blank?
                  backend = backend_names.dig(w.worker_id, :value)
                end
                shard = backend_shards.dig(w.client_id, :value)
                if shard.blank?
                  shard = backend_shards.dig(w.worker_id, :value)
                end

                # Replace the backend and shard with the values the gateway would resolve to
                w.set_backend(backend)
                w.set_shard(shard.to_s.empty? ? "any" : shard)

                key = "#{listener_state}|#{backend}|#{active}"
                if w.listener_state == listener_state && w.active? == active
                  if workers_by_state_counts.has_key? key
                    workers_by_state_counts[key].count += 1
                  else
                    # the process list doesn't always have workers for every non-gateway backend
                    workers_by_state_counts[key] = CountByState.new(
                      count: 1,
                      state: (active ? :active : :idle),
                      listener_state: listener_state,
                      backend: backend,
                      )
                  end
                elsif !workers_by_state_counts.has_key? key
                  # reset gauges for non-matching listener state or active status back to 0, since the gateway resolved
                  # backends may not have been in the process list
                  workers_by_state_counts[key] = CountByState.new(
                    count: 0,
                    state: (active ? :active : :idle),
                    listener_state: listener_state,
                    backend: backend,
                    )
                end
              end
            end
          end
        end
      end

      workers_by_state_counts.each do |_, count|
        stats.aqueduct_workers_by_state << count
      end

      stats.aqueduct_idle_workers = aqueduct_workers.count(&:idle?)
      stats.aqueduct_active_workers = aqueduct_workers.count(&:active?)
      stats.aqueduct_stale_workers = aqueduct_workers.count(&:stale?)
      stats.aqueduct_total_workers = aqueduct_workers.count

      aqueduct_workers.filter(&:active?).map(&:queue).tally.each do |queue, count|
        stats.aqueduct_active_workers_by_queue << CountByQueue.new(
          count: count,
          queue: queue,
        )
      end

      stats.aqueduct_listener_shas = aqueduct_workers.map(&:listener_sha).compact.uniq.count
      stats.aqueduct_worker_shas = aqueduct_workers.map(&:sha).compact.uniq.count

      stats.aqueduct_stalled_listeners = aqueduct_workers.map(&:listener).compact.uniq.count(&:stalled?)

      assign_non_gateway_shards(aqueduct_workers)

      aqueduct_workers
        .filter(&:shard)
        .group_by { |w| [w.backend, w.shard] }
        .each do |(backend, shard), workers|
          stats.aqueduct_workers_by_shard << CountByShard.new(
            count: workers.count,
            backend: backend,
            shard: shard,
          )

          stats.aqueduct_active_workers_by_shard << CountByShard.new(
            count: workers.count(&:active?),
            backend: backend,
            shard: shard,
          )
        end

      stats
    end

    private

    # Internal: Parse out worker state from a list of worker processes.
    def parse_workers
      procs = @get_procs.call

      listeners = procs.reduce({}) do |hash, line|
        if line =~ RESQUED_LISTENER_RE
          listener = Listener.new(
            pid: $~["pid"].to_i,
            ppid: $~["ppid"].to_i,
            etime: $~["etime"],
            sha: $~["sha"],
            state: $~["state"],
          )
          hash[listener.pid] = listener
        end

        hash
      end

      aqueduct_workers = []

      procs.each do |line|
        case
        when match = line.match(AQUEDUCT_WORKER_RE)
          pid, ppid = match["pid"].to_i, match["ppid"].to_i
          aqueduct_workers << Worker.new(
            pid: pid,
            ppid: ppid,
            listener: listeners[ppid],
            backend: match["backend"],
            sha: match["sha"],
            state: match["state"],
            status: @status_client.get(pid: pid),
            since: match["since"],
            etime: match["etime"],
          )
        end
      end

      aqueduct_workers
    end

    # Internal: Query aqueduct for shards assigned to workers and update worker records with shard
    # IDs. Relevant when gateway feature flags are enabled at less than 100%.
    def assign_non_gateway_shards(workers)
      workers
        .filter { |w| w.status? && w.backend != GATEWAY_BACKEND_NAME }
        .group_by(&:backend_url)
        .map do |backend_url, workers|

        resp = @shard_id_client.get(
          url: backend_url,
          clients: workers.map { |w| { client_id: w.client_id, tags: w.tags } },
          workers: workers.map { |w| { id: w.worker_id, tags: w.tags } }
        ) || {}

        backend_ids = resp[:backend_ids] || {}
        unless backend_ids.length == 0
          workers.each do |w|
            # Prefer client_id to support server-side cutover to worker_id when client_id omitted
            shard = backend_ids.dig(w.client_id, :value)
            if shard.blank?
              shard = backend_ids.dig(w.worker_id, :value)
            end
            w.set_shard(shard.to_s.empty? ? "any" : shard)
          end
        end
      end
    end

    class Results
      attr_accessor :aqueduct_workers_by_state,
        :aqueduct_idle_workers, :aqueduct_active_workers, :aqueduct_total_workers,
        :aqueduct_workers_by_shard, :aqueduct_active_workers_by_shard,
        :aqueduct_active_workers_by_queue, :aqueduct_listener_shas, :aqueduct_worker_shas,
        :aqueduct_stale_workers, :aqueduct_stalled_listeners,
        :deployable

      def initialize
        @aqueduct_workers_by_state = []
        @aqueduct_workers_by_shard = []
        @aqueduct_active_workers_by_shard = []
        @aqueduct_active_workers_by_queue = []
      end
    end

    class CountByState
      attr_reader :count, :state, :listener_state, :backend
      attr_writer :count

      def initialize(count:, state:, listener_state:, backend: nil)
        @count, @state, @listener_state, @backend = count, state, listener_state, backend
      end

      def to_h
        { count: count, state: state, listener_state: listener_state, backend: backend }
      end
    end

    class CountByShard
      attr_reader :count, :backend, :shard

      def initialize(count:, backend:, shard:)
        @count, @backend, @shard = count, backend, shard
      end

      def to_h
        { count: count, backend: backend, shard: shard }
      end
    end

    class CountByQueue
      attr_reader :count, :queue

      def initialize(count:, queue:)
        @count, @queue = count, queue
      end

      def to_h
        { count: count, queue: queue }
      end
    end

    class StatusClient
      def initialize(read_timeout: 1)
        @read_timeout = read_timeout
      end

      def get(pid:)
        socket = UNIXSocket.new("#{base_path}/workers/#{pid}")
        socket.puts("status")

        unless IO.select([socket], nil, nil, @read_timeout)
          return
        end

        JSON.parse(socket.gets)
      rescue => e # rubocop:todo Lint/RescueException
        raise(e) if ENV["DEBUG"]
        nil
      end

      def base_path
        "/var/tmp"
      end
    end

    class ProtobufShardIdClient
      def initialize(read_timeout: 5, aqueduct_urls: [])
        @clients = {}
        aqueduct_urls.map do |url|
          @clients[url] = GitHub.build_aqueduct_client(
            client_id: "#{GitHub.aqueduct_app_name}-worker-metrics",
            url: url,
            circuit_breaker: nil)
        end
      end

      def get(url:, clients: [], workers: [])
        client = @clients[url]
        resp = client.backend_ids(clients: clients, workers: workers)
        resp.to_h
      rescue => e # rubocop:todo Lint/RescueException
        raise(e) if ENV["DEBUG"]
        nil
      end

    end

    class Etime
      # ps -o etime outputs 'elapsed time since the process was started, in the form [[DD-]hh:]mm:ss.'
      ETIME_RE = /((?<days>\d+)-)?((?<hours>\d\d):)?(?<minutes>\d\d):(?<seconds>\d\d)/

      # Internal: Parse an etime string and return elapsed time in seconds.
      def self.parse(etime)
        if match = etime.match(ETIME_RE)
          match["days"].to_i * 24 * 60 * 60 +
          match["hours"].to_i * 60 * 60 +
          match["minutes"].to_i * 60 +
          match["seconds"].to_i
        end
      end
    end

    class Listener
      attr_reader :pid, :ppid, :sha, :state

      def initialize(pid:, ppid:, etime:, sha:, state:)
        @pid = pid
        @ppid = ppid
        @sha = sha
        @state = state
        @elapsed = Etime.parse(etime)
      end

      def shutdown?
        @state == "shutdown"
      end

      def stalled?
        @elapsed && @elapsed > STALLED_LISTENER_TIMEOUT
      end
    end

    class Worker
      attr_reader :pid, :status, :listener, :sha

      def initialize(pid:, ppid:, etime:, listener:, sha:, state:, since: nil, backend: nil, status: nil)
        @pid = pid
        @ppid = ppid
        @listener = listener
        @backend = backend
        @status = status || {}
        @sha = sha
        @active = state == "Processing"
        @since = since&.to_i
        @elapsed = Etime.parse(etime)
      end

      def active?
        @active
      end

      def idle?
        !active?
      end

      def status?
        !status.empty?
      end

      def stale?
        return unless @since
        return unless @listener&.shutdown?

        (Time.now - Time.at(@since)) >= STALE_THRESHOLD
      end

      def listener_state
        @listener&.state || ORPHANED_WORKER
      end

      def listener_sha
        @listener&.sha
      end

      def queue
        status.dig("current_job", "queue")
      end

      def backend_url
        status["backend_url"]
      end

      def backend
        status["backend"] || @backend
      end

      def set_shard(shard)
        status["shard"] = shard
      end

      def set_backend(backend)
        status["backend"] = backend
        @backend = backend
      end

      def shard
        status["shard"]
      end

      def client_id
        status["client_id"]
      end

      def tags
        status["tags"]
      end

      def publishing_app
        status.dig("current_job", "app")
      end

      def worker_id
        status["worker_id"]
      end
    end
  end
end
