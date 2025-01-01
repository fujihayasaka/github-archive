# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_writer :language_stats
    def language_stats(commit_oid, incremental, tree_size = nil)
      git_linguist("stats", commit_oid, incremental, tree_size) || {}
    end

    rpc_writer :language_breakdown_by_file
    def language_breakdown_by_file(commit_oid, incremental)
      git_linguist("breakdown", commit_oid, incremental) || {}
    end

    rpc_writer :clear_language_cache
    def clear_language_cache
      git_linguist("clear")
    end

    protected

    # External process helper
    def git_linguist(command, commit = nil, incremental = true, tree_size = nil)
      argv = [command]
      argv << "--commit=#{commit}" if commit
      argv << "--tree-size=#{tree_size}" if tree_size
      argv << "--force" unless incremental
      res = spawn_git("linguist", argv)
      if !res["ok"]
        raise GitRPC::Error, "git-linguist failed: #{res["err"]}"
      end
      if res["out"].empty?
        nil
      else
        JSON.parse(res["out"])
      end
    end
  end
end
