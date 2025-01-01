# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsCacheSizeLimit
    include Instrumentation::Model
    MAX_REPO_CACHE_SIZE_LIMIT_KEY = "actions_max_repo_cache_size_limit".freeze
    REPO_CACHE_SIZE_LIMIT_KEY = "actions_repo_cache_size_limit".freeze
    MIN = 1.freeze
    MAX = 25.freeze
    DEFAULT = 10.freeze

    def actions_cache_size_limit
      value = config.get(REPO_CACHE_SIZE_LIMIT_KEY) || DEFAULT
      [value.to_i, max_allowed_actions_cache_size_limit.to_i].min
    end

    # Max actions cache size limit
    def max_allowed_actions_cache_size_limit
      config.get(MAX_REPO_CACHE_SIZE_LIMIT_KEY) || MAX
    end

    def set_actions_cache_size_limit_enterprise(limit:, upper_limit:, actor:)
      if upper_limit.present?
        raise ActionsCacheUsagePolicy::InvalidLimitError.new("Maximum repository cache size limit (max_repo_cache_size_limit_in_gb) must be greater than or equal to #{MIN}") if upper_limit < MIN
        raise ActionsCacheUsagePolicy::InvalidLimitError.new("Repository cache size limit of #{limit} must be between #{MIN} and #{upper_limit}(max_repo_cache_size_limit_in_gb).") if !limit.nil? && !limit.between?(MIN, upper_limit)
      else
        raise ActionsCacheUsagePolicy::InvalidLimitError.new("Repository cache size limit of #{limit} must be between #{MIN} and #{max_allowed_actions_cache_size_limit}(max_repo_cache_size_limit_in_gb).") if !limit.nil? && !limit.between?(MIN, max_allowed_actions_cache_size_limit.to_i)
      end

      config.set(MAX_REPO_CACHE_SIZE_LIMIT_KEY, upper_limit.to_s, actor) if !upper_limit.nil?
      config.set(REPO_CACHE_SIZE_LIMIT_KEY, limit.to_s, actor) if !limit.nil?

      instrument "set_actions_cache_size_limit_enterprise", actor: actor, limit: limit, upper_limit: upper_limit
    end

    def set_actions_cache_size_limit(limit:, actor:)
      raise ActionsCacheUsagePolicy::InvalidLimitError.new("Repository cache size limit must be between #{MIN} and #{max_allowed_actions_cache_size_limit}.") unless limit.between?(MIN, max_allowed_actions_cache_size_limit.to_i)

      config.set(REPO_CACHE_SIZE_LIMIT_KEY, limit.to_s, actor)

      instrument "set_actions_cache_size_limit", actor: actor, limit: limit
    end
  end
end
