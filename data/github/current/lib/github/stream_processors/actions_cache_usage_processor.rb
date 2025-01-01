# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class ActionsCacheUsageProcessor < SingleMessageProcessor
      DEFAULT_GROUP_ID = "actions_cache_usage_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.actions\.v0\.CacheUsage\Z/

      options[:session_timeout] = 60.seconds
      options[:socket_timeout] = 65.seconds
      options[:start_from_beginning] = false
      options[:min_bytes] = 1
      options[:max_wait_time] = 1.second
      options[:max_bytes_per_partition] = 100.kilobytes

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
      end

      # Public: Process a single CacheUsage message and persist cache data
      #
      # message - The Hydro::CacheUsage message to process
      #
      # Returns nothing
      sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
      def process_message(message)
        active_caches_size = message.value[:active_caches_size_in_bytes]
        active_caches_count = message.value[:active_caches_count]
        created_at_in_seconds = message.value.dig(:created_at, :seconds)
        is_results_usage = message.value[:is_results_usage]

        GitHub.dogstats.increment("actions_cache_usage.hydro_message.process", tags: ["source:#{is_results_usage ? "results" : "artifact_cache"}"])

        if created_at_in_seconds.nil?
          created_at = Time.now
        else
          created_at = Time.at(created_at_in_seconds)
        end

        repo = repository(message)
        if repo.nil?
          message.skip("repo_not_found")
          return
        end
        owner_id = repo.owner_id
        ActionsCacheUsageHelper.save_repo_cache_usage(repo, active_caches_size, active_caches_count, owner_id, created_at, is_results_usage)
      end

      def repository(message)
        repo_id = if !message.value[:repository_id].zero?
          message.value[:repository_id]
        else
          Platform::Helpers::NodeIdentification.from_global_id(message.value[:global_id]).last
        end

        Repositories::Public.find_active!(repo_id)
      end
    end
  end
end
