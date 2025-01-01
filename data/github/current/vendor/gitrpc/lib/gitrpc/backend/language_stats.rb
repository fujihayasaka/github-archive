# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "linguist"
require "scout/cache_helper"
require "gitrpc/backend/language_stats/repository"

module GitRPC
  class Backend
    LINGUIST_GITRPC_CACHE_VERSION = "v3:gitrpc:#{Linguist::VERSION}"

    rpc_writer :language_stats
    def language_stats(commit_oid, incremental, tree_size = nil)
      git_linguist("stats", commit_oid, incremental, tree_size) || {}
    end

    rpc_writer :alternative_language_stats
    def alternative_language_stats(commit_oid, incremental, tree_size = nil, write_cache: true)
      # Load stats
      repo = linguist_repo(commit_oid, incremental, tree_size)
      stats = repo.languages

      # Update cache (if needed)
      write_linguist_cache(commit_oid, repo) if write_cache

      stats
    ensure
      repo&.repository&.close_readers
    end

    rpc_writer :language_breakdown_by_file
    def language_breakdown_by_file(commit_oid, incremental)
      git_linguist("breakdown", commit_oid, incremental) || {}
    end

    rpc_writer :alternative_language_breakdown_by_file
    def alternative_language_breakdown_by_file(commit_oid, incremental, write_cache: true)
      # Load breakdown
      repo = linguist_repo(commit_oid, incremental)
      breakdown = repo.breakdown_by_file

      # Update cache (if needed)
      write_linguist_cache(commit_oid, repo) if write_cache

      breakdown
    ensure
      repo&.repository&.close_readers
    end

    rpc_writer :clear_language_cache
    def clear_language_cache
      git_linguist("clear")
    end

    rpc_writer :alternative_clear_language_cache
    def alternative_clear_language_cache
      fs_delete(::Scout::CacheHelper::LANGUAGE_CACHE_PATH)
    rescue GitRPC::SystemError
    end

    def load_linguist_cache
      version, oid, file_map = load_cache_file(::Scout::CacheHelper::LANGUAGE_CACHE_PATH)
      if [::Scout::CacheHelper::LANGUAGE_STATS_CACHE_VERSION, LINGUIST_GITRPC_CACHE_VERSION].include?(version)
        [file_map, oid]
      else
        [nil, nil]
      end
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

    private

    def write_linguist_cache(oid, repo)
      write_cache_file(
        ::Scout::CacheHelper::LANGUAGE_CACHE_PATH,
        [
          LINGUIST_GITRPC_CACHE_VERSION,
          oid,
          repo.cache
        ]
      )
    end

    def linguist_repo(commit_oid, incremental, tree_size = nil)
      source = LanguageStats::Repository.new(self)
      tree_size ||= Linguist::Repository::MAX_TREE_SIZE
      if incremental
        old_stats, old_commit_oid = load_linguist_cache
        if old_commit_oid && old_stats
          Linguist::Repository.incremental(source, commit_oid, old_commit_oid, old_stats, tree_size)
        else
          Linguist::Repository.new(source, commit_oid, tree_size)
        end
      else
        Linguist::Repository.new(source, commit_oid, tree_size)
      end
    end
  end
end
