# typed: true
# frozen_string_literal: true

module Elastomer

  class Reindex

    TASK_KEY = "task".freeze
    SOURCE_INDEX_KEY = "source_index".freeze
    FINISHED_KEY = "finished".freeze

    def initialize(source_index, destination_index, cluster)
      @destination_index = destination_index
      @source_index = redis.hget(group_key, SOURCE_INDEX_KEY) || source_index
      cluster = ::Elastomer.router.cluster_for_index(@source_index) if cluster.nil?
      @cluster_name = cluster
      @task_id = redis.hget(group_key, TASK_KEY) || nil
      @client = ::Elastomer.router.client(@cluster_name)
    rescue ElastomerClient::Client::ServerError => error
      @server_error = error
    end

    # The ID of the reindex task
    attr_reader :task_id

    def start
      body = {
        source: { index: @source_index },
        dest: { index: @destination_index.name }
      }

      source = @client.index(@source_index)
      if !source.exists?
        return { elastomer_client_error: "Source index does not exist" }
      end

      num_slices = @client.index(@source_index).get_settings[@source_index]["settings"]["index"]["number_of_shards"].to_i

      response = @client.reindex.reindex(body, wait_for_completion: false, slices: 32, requests_per_second: 200)
      @task_id = response["task"]
      redis.hset(group_key, TASK_KEY, @task_id)
      redis.hset(group_key, SOURCE_INDEX_KEY, @source_index)
    end

    def rethrottle(requests_per_second)
      @client.reindex.rethrottle(@task_id, requests_per_second: requests_per_second)
    end

    def status(params = {})
      return @status if defined?(@status) && (@status["completed"] || @status["error"] || @status["task"]["canceled"])

      return { not_started: true } if @task_id.nil?

      node_id = @task_id.split(":").first
      task_id = @task_id.split(":").last.to_i
      begin
        response = @client.tasks.get_by_id(node_id, task_id, params)
        @status = response
        response
      rescue ElastomerClient::Client::RequestError => ex
        { elastomer_client_error: "An error occurred while fetching the reindex status" }
      end
    end

    def exists?
      redis.hget(group_key, TASK_KEY) ? true : false
    end

    def finished?
      finish_state = redis.hget(group_key, FINISHED_KEY)
      return true if %w[completed error canceled].include?(finish_state)

      status_state = if status["completed"]
        "completed"
      elsif status["error"]
        "error"
      elsif status.dig("task", "canceled")
        "canceled"
      end
      if status_state
        redis.hset(group_key, FINISHED_KEY, status_state)
        return true
      end

      false
    end

    def cancel
      @client.tasks.cancel(task_id: @task_id) unless finished?
    end

    sig { returns(Float) }
    def progress
      return 100.0 if finished?
      query = { query: { match_all: {} } }
      source_count = @client.index(@source_index).docs.count(query)
      dest_count = @client.index(@destination_index.name).docs.count(query)
      return 0.0 if source_count["count"] == 0
      (dest_count["count"].to_f / source_count["count"].to_f) * 100
    end

    def estimated_completion_time
      return stats[:finished] if finished?

      p = progress
      return nil unless p > 0

      started = stats[:started]
      estimated_duration = (Time.now - started).to_f * (100.0 / p)
      started + estimated_duration
    end

    def stats
      hash = {}
      if status[:elastomer_client_error]
        hash[:reindex_error] = status[:elastomer_client_error]
        return hash
      end
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

    def group_key
      return @group_key if defined?(@group_key)
      @group_key = "#{self.class.name}/#{@destination_index.name}"
    end

    def reset!
      redis.del(group_key)
      self
    end

    # Internal: Return the redis connection to use for requests.
    def redis
      GitHub.job_coordination_redis
    end
    private :redis
  end
end
