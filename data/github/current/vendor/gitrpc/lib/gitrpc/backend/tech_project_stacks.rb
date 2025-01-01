# typed: true
# frozen_string_literal: true

require "linguist"
require "scout/stack"
require "scout/tech_stack"
require "gitrpc/backend/project_stats/project_analysis"

module GitRPC
  class Backend
    rpc_writer :tech_project_stacks
    def tech_project_stacks(commit_oid, forced_rescan)
      scout("stacks-list", commit_oid, forced_rescan) || {}
    end

    rpc_writer :alternative_tech_project_stacks
    def alternative_tech_project_stacks(commit_oid, forced_rescan, write_cache: true)
      analysis = ProjectStats::ProjectAnalysis.new(self, commit_oid, forced_rescan, write_cache)
      analysis.get_repository_projects.map(&:to_h)
    ensure
      analysis&.repo&.repository&.close_readers
    end

    private

    # Another external process helper
    def scout(command, commit_oid, forced_rescan = false)
      argv = ["scout", command]
      argv << "--commit=#{commit_oid}" if commit_oid
      argv << "-f" if forced_rescan
      res = spawn(argv)
      if !res["ok"]
        raise GitRPC::Error, "scout failed: #{res["err"]}"
      end
      if res["out"].empty?
        nil
      else
        JSON.parse(res["out"])
      end
    end
  end
end
