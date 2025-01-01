# typed: true
# frozen_string_literal: true

class KnowledgeBase
  class ScopingQuery

    SourceRepo = T.type_alias do
      {
          id: Integer,
          owner_id: Integer,
          paths: T::Array[String]
      }
    end

    attr_reader :source_repos, :query

    # Takes an array of source repos and turns them into the query we send to Blackbird
    sig { params(source_repos: T::Array[SourceRepo]).returns(String) }
    def self.from_source_repositories(source_repos:)
      new(source_repos:).build
    end

    sig { returns(T::Array[SourceRepo]) }
    def source_repositories
      return [] if query.blank?

      repo_names = []
      paths_for_last_repo = []
      paths_by_repo_name = {}

      # scan the query, matching either a repo: or path: qualifier
      query.scan(/(?:repo:([^ ^\)]+))|(?:path:([^ ^\)]+))/) do |repo_name, path|
        if repo_name.present?
          paths_for_last_repo = []
          repo_names << repo_name
        elsif path.present?
          paths_for_last_repo << path
        end

        paths_by_repo_name[repo_names.last] = paths_for_last_repo
      end

      Repository.with_names_with_owners(repo_names).map do |repo|
        paths = paths_by_repo_name[repo.name_with_display_owner] || []
        { id: repo.id, owner_id: repo.owner_id, paths: }
      end
    end

    def initialize(source_repos: nil, query: nil)
      @source_repos = source_repos
      @query = query
    end

    sig { returns(String) }
    def build
      qualifiers = []
      source_repos.each do |source_repo|
        source_repo = source_repo.symbolize_keys
        repo = Repositories::Public.find_active(source_repo[:id])
        next if repo.nil?

        qualifier = if source_repo[:paths].empty?
          "repo:#{repo.name_with_display_owner}"
        else
          path_qualifiers = source_repo[:paths].map { |path| "path:#{path}" }.join(" OR ")
          "(repo:#{repo.name_with_display_owner} (#{path_qualifiers}))"
        end

        qualifiers << qualifier
      end

      qualifiers.join(" OR ")
    end
  end
end
