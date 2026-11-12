# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module StatsAllowlistCache
      # How many metric names each allowlist client remembers. GHES only, set in
      # `environments/enterprise.rb`. 0 turns the cache off.
      sig { returns(T.nilable(Integer)) }
      attr_accessor :stats_allowlist_cache_size
    end
  end

  extend Config::StatsAllowlistCache
end
