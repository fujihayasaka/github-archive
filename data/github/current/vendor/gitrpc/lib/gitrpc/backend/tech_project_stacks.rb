# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_writer :tech_project_stacks
    def tech_project_stacks(commit_oid, forced_rescan)
      scout("stacks-list", commit_oid, forced_rescan) || {}
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
