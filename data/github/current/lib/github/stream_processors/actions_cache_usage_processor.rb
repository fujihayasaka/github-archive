# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class ActionsCacheUsageProcessor < BaseProcessor
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

      def batching?
        false
      end

      # Public: Process a single CacheUsage message and persist cache data
      #
      # message - The Hydro::CacheUsage message to process
      #
      # Returns nothing
      def process_message(message)
        GitHub.dogstats.increment("actions_cache_usage.hydro_message.process", tags: ["action:process_hydro_message"])
        active_caches_size = message.value[:active_caches_size_in_bytes]
        active_caches_count = message.value[:active_caches_count]
        global_id = message.value[:global_id]
        created_at_in_seconds = message.value.dig(:created_at, :seconds)

        if created_at_in_seconds.nil?
          created_at = Time.now
        else
          created_at = Time.at(created_at_in_seconds)
        end

        repo_id = Platform::Helpers::NodeIdentification.from_global_id(global_id).last
        repo = Repositories::Public.find_active!(repo_id)
        if repo.nil?
          message.skip("repo_not_found")
          return
        end
        owner_id = repo.owner_id

        ActionsCacheUsageHelper.save_repo_cache_usage(repo_id, active_caches_size, active_caches_count, owner_id, created_at)
      end
    end
  end
end
