# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    def tech_project_stacks(commit_oid, forced_rescan = false)
      ensure_valid_full_oid(commit_oid)
      if self.feature_enabled?(:language_project_stats_git)
        send_message(:alternative_tech_project_stacks, commit_oid, forced_rescan)
      else
        science "tech_project_stacks_git_experiment" do |e|
          e.context({ repository_key: repository_cache_key, commit_oid:, forced_rescan: })
          e.use { send_message(:tech_project_stacks, commit_oid, forced_rescan) }
          e.try { send_message(:alternative_tech_project_stacks, commit_oid, forced_rescan, write_cache: false) }
        end
      end
    end
  end
end
