# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "linguist"
require "scout/cache_helper"

module GitRPC
  class Backend
    rpc_writer :language_stats
    def language_stats(commit_oid, incremental, tree_size = nil, write_cache: true)
      git_language_stats("stats", commit_oid, incremental, tree_size, write_cache:) || {}
    end

    rpc_writer :language_breakdown_by_file
    def language_breakdown_by_file(commit_oid, incremental, write_cache: true)
      git_language_stats("breakdown", commit_oid, incremental, write_cache:) || {}
    end

    rpc_writer :clear_language_cache
    def clear_language_cache
      fs_delete(::Scout::CacheHelper::LANGUAGE_CACHE_PATH)
    rescue GitRPC::SystemError
    end

    private

    def git_language_stats(command, commit = nil, incremental = true, tree_size = nil, write_cache: true)
      argv = [command]
      argv << "--commit=#{commit}" if commit
      argv << "--tree-size=#{tree_size}" if tree_size
      argv << "--force" unless incremental
      argv << "--disable-write-cache" unless write_cache
      res = spawn_git("language-project-stats", argv)
      if !res["ok"]
        raise GitRPC::Error, "git-language-project-stats failed: #{res["err"]}"
      end
      if res["out"].empty?
        nil
      else
        JSON.parse(res["out"])
      end
    end
  end
end
