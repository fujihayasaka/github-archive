# typed: true
# frozen_string_literal: true

module Elastomer

  class Reindex
    def initialize(source_index, destination_index, cluster)
      cluster = ::Elastomer.router.cluster_for_index(source_index) if cluster.nil?

      @source_index = source_index
      @destination_index = destination_index
      @cluster_name = cluster
      @task_id = nil
      @client = ::Elastomer.router.client(@cluster_name)
    rescue ElastomerClient::Client::ServerError => error
      @server_error = error
    end

    # The ID of the reindex task
    attr_reader :task_id

    def start
      body = {
        source: { index: @source_index },
        dest: { index: @destination_index }
      }
      response = @client.reindex.reindex(body, { wait_for_completion: false })
      @task_id = response["task"]
    end

    def status(params = {})
      return @status if defined?(@status) && (@status["completed"] || @status["error"] || @status["task"]["canceled"])

      node_id = @task_id.split(":").first
      task_id = @task_id.split(":").last.to_i
      response = @client.tasks.get_by_id(node_id, task_id, params)

      @status = response
      response
    end

    def finished?
      status["completed"] || status["error"] || status["task"]["canceled"]
    end

    def cancel
      @client.tasks.cancel(task_id: @task_id)
    end

    def progress
      return 100.0 if finished?
      source_count = @client.index(@source_index).docs.count
      dest_count = @client.index(@destination_index).docs.count
      return 0.0 if source_count == 0
      dest_count / source_count * 100
    end

    def estimated_completion_time
      return stats[:finished] if finished?

      p = progress
      return nil unless p && p > 0

      started = stats[:started]
      estimated_duration = (Time.now - started).to_f * (100.0 / p)
      started + estimated_duration
    end

    def stats
      hash = {}
      ms = status["task"]["start_time_in_millis"]
      hash[:started] = Time.at(ms / 1000, (ms % 1000) * 1000)
      hash[:elapsed] = status["task"]["running_time_in_nanos"] / 1_000_000_000.0
      hash[:finished] = finished? ? hash[:started] + hash[:elapsed] : nil

      hash[:total] = status["task"]["status"]["total"]
      hash[:updated] = status["task"]["status"]["updated"]
      hash[:added] = status["task"]["status"]["created"]
      hash[:removed] = status["task"]["status"]["deleted"]

      hash
    end

    # def reset

    # end
  end
end
