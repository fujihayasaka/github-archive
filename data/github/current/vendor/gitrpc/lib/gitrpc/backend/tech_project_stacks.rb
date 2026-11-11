# typed: true
# frozen_string_literal: true

module GitRPC
  class Backend
    rpc_writer :tech_project_stacks
    def tech_project_stacks(commit_oid, forced_rescan, write_cache: true)
      git_project_stats("stacks-list", commit_oid, forced_rescan, write_cache:) || {}
    end

    private

    def git_project_stats(command, commit_oid, forced_rescan = false, write_cache: true)
      argv = [command]
      argv << "--commit=#{commit_oid}" if commit_oid
      argv << "--f" if forced_rescan
      argv << "--disable-write-cache" unless write_cache
      res = spawn_git("language-project-stats", argv)
      if !res["ok"]
        raise GitRPC::Error, "git language-project-stats failed: #{res["err"]}"
      end
      if res["out"].empty?
        nil
      else
        JSON.parse(res["out"])
      end
    end
  end
end
