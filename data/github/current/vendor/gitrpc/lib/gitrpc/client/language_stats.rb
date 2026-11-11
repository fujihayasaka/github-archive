# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    def language_stats(commit_oid, incremental = true, tree_size = nil)
      ensure_valid_full_oid(commit_oid)
      send_message(:language_stats, commit_oid, incremental, tree_size)
    end

    def language_breakdown_by_file(commit_oid, incremental = true)
      ensure_valid_full_oid(commit_oid)
      send_message(:language_breakdown_by_file, commit_oid, incremental)
    end

    def clear_language_cache
      send_message(:clear_language_cache)
    end
  end
end
