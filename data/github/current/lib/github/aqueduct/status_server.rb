# typed: true
# frozen_string_literal: true

require "github/aqueduct/socket_server"

# An RPC server for aqueduct worker processes.
#
# Used by Resqued::MetricsReporter and script/resqued-metrics by way of Resqued::WorkerMetrics
module GitHub
  module Aqueduct
    class StatusServer
      def initialize(worker:)
        @worker = worker
        @client_id = GitHub.aqueduct_client_id
        @tags = GitHub.aqueduct_tags
      end

      def run
        server = GitHub::Aqueduct::SocketServer.new(file: file)
        server.on("status") { handle_status }
        server.on("current_job") { handle_current_job }
        server.run
      end

      private

      attr_reader :worker

      # Internal: Generate the UNIX socket file name.
      def file
        base_dir = "/var/tmp"
        FileUtils.mkdir_p("#{base_dir}/workers")
        "#{base_dir}/workers/#{Process.pid}"
      end

      def handle_status
        status = {
          client_id: @client_id,
          worker_id: worker.worker_id,
          tags: @tags,
          pid: Process.pid,
          runtime: time_since_boot,
          current_ref: GitHub.current_ref,
          revision: GitHub.current_sha,
        }

        if (job = worker.current_job)
          status[:current_job] = {
            processing_started_at: worker.current_job_started_at,
            last_heartbeat_at: worker.last_heartbeat_at,
            app: job.app,
            queue: job.queue,
            aqueduct_job_id: job.id,
          }
        end

        if (backend = worker.backend)
          if backend.respond_to?(:backend_status)
            status.merge!(backend.backend_status)
          end
        end

        # backend_url in status server is used to query the aqueduct API for redis shard information
        status.to_json
      end

      def handle_current_job
        response = {
          client_id: @client_id,
          worker_id: worker.worker_id,
          tags: @tags,
          pid: Process.pid,
          runtime: time_since_boot,
          current_ref: GitHub.current_ref,
          revision: GitHub.current_sha,
        }

        if (job = worker.current_job)
          job_data = {
            app: job.app,
            queue: job.queue,
            aqueduct_job_id: job.id,
            headers: job.headers,
            processing_started_at: worker.current_job_started_at,
            last_heartbeat_at: worker.last_heartbeat_at,
            processing_elapsed_sec: Time.now - worker.current_job_started_at,
          }

          begin
            parsed_payload = JSON.parse(job.payload)
            payload = parsed_payload.fetch("payload")
            metadata = parsed_payload.fetch("metadata")

            # Top-level the most useful payload fields
            job_data[:queued_at] = metadata.fetch("queued_at")
            job_data[:active_job_id] = payload.fetch("job_id")
            job_data[:job_class] = payload.fetch("job_class")
            job_data[:arguments] = payload.fetch("arguments")

            job_data[:parsed_payload] = parsed_payload
          rescue => e
            job_data[:unparsed_payload] = job.payload
            parse_error = [e]
            backtrace = e.backtrace
            if backtrace
              parse_error = parse_error.concat(backtrace)
            end
            job_data[:parse_error] = parse_error
          end

          response[:current_job] = job_data
        end

        response.to_json
      end

      def time_since_boot
        Process.clock_gettime(Process::CLOCK_MONOTONIC).to_i - GitHub::BootMetrics.initial_boot_time.to_i
      end
    end
  end
end
