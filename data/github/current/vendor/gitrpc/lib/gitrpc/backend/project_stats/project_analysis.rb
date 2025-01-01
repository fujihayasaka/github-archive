# typed: true
# frozen_string_literal: true

require "linguist"
require "scout/project_analysis"
require "scout/repository"
require "gitrpc/backend/language_stats/repository"

module GitRPC
  class Backend
    # This module contains simple subclasses around the Scout CacheHelper,
    # Repository, and ProjectAnalysis whose main purpose is allow us to use
    # GitRPC to read/write caches with custom versions.
    module ProjectStats
      class CacheHelper < ::Scout::CacheHelper
        SCOUT_GITRPC_CACHE_VERSION = "v0:gitrpc:#{::Scout::VERSION}"

        def initialize(backend, write_cache)
          @backend = backend
          @git_dir = @backend.path
          @write_cache = write_cache
        end

        def load_stacks_map_from_cache
          version, oid, file_map = @backend.load_cache_file(::Scout::CacheHelper::PROJECTS_CACHE_PATH)
          if [::Scout::CacheHelper::PROJECTS_STATS_CACHE_VERSION, SCOUT_GITRPC_CACHE_VERSION].include?(version)
            [file_map, oid]
          else
            [nil, nil]
          end
        end

        def load_languages_from_cache
          @backend.load_linguist_cache
        end

        def save_stacks_cache(commit_oid, result)
          return unless @write_cache
          @backend.write_cache_file(
            ::Scout::CacheHelper::PROJECTS_CACHE_PATH,
            [
              SCOUT_GITRPC_CACHE_VERSION,
              commit_oid,
              result
            ]
          )
        end
      end

      class Repository < ::Scout::Repository
        def initialize(backend, commit_oid, write_cache)
          super(LanguageStats::Repository.new(backend), commit_oid)
          @cache_helper = CacheHelper.new(backend, write_cache)
        end
      end

      class ProjectAnalysis < ::Scout::ProjectAnalysis
        def initialize(backend, incoming_commit_oid, forced_rescan, write_cache)
          @forced_rescan = forced_rescan
          @commit_oid = incoming_commit_oid
          @repo = Repository.new(backend, commit_oid, write_cache)
        end
      end
    end
  end
end
