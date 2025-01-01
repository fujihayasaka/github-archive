# typed: true
# frozen_string_literal: true

module GitRPC
  class Client
    def language_stats(commit_oid, incremental = true, tree_size = nil)
      ensure_valid_full_oid(commit_oid)
      if self.feature_enabled?(:language_project_stats_git)
        send_message(:alternative_language_stats, commit_oid, incremental, tree_size)
      else
        science "language_stats_git_experiment" do |e|
          e.context({ repository_key: repository_cache_key, commit_oid:, tree_size: })
          e.use { send_message(:language_stats, commit_oid, incremental, tree_size) }
          e.try { send_message(:alternative_language_stats, commit_oid, incremental, tree_size, write_cache: false) }
          e.run_if { !GitRPC::Client.disable_experiments? }
        end
      end
    end

    def language_breakdown_by_file(commit_oid, incremental = true)
      ensure_valid_full_oid(commit_oid)
      if self.feature_enabled?(:language_project_stats_git)
        send_message(:alternative_language_breakdown_by_file, commit_oid, incremental)
      else
        science "language_breakdown_by_file_git_experiment" do |e|
          e.context({ repository_key: repository_cache_key, commit_oid: })
          e.use { send_message(:language_breakdown_by_file, commit_oid, incremental) }
          e.try { send_message(:alternative_language_breakdown_by_file, commit_oid, incremental, write_cache: false) }
          e.run_if { !GitRPC::Client.disable_experiments? }
        end
      end
    end

    def clear_language_cache
      if self.feature_enabled?(:language_project_stats_git)
        send_message(:alternative_clear_language_cache)
      else
        send_message(:clear_language_cache)
      end
    end
  end
end
