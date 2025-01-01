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

    attr_reader :source_repos, :query, :current_user

    # Takes an array of source repos and turns them into the query we send to Blackbird
    sig { params(source_repos: T::Array[SourceRepo], current_user: User).returns(String) }
    def self.from_source_repositories(source_repos:, current_user:)
      new(source_repos:, current_user:).build
    end

    def initialize(source_repos: nil, query: nil, current_user: nil)
      @source_repos = source_repos
      @query = query
      @current_user = current_user
    end

    sig { returns(String) }
    def build
      qualifiers = []
      source_repos.each do |source_repo|
        source_repo = source_repo.symbolize_keys
        repo = Repositories::Public.find_active(source_repo[:id])
        next if repo.nil?

        qualifier = if source_repo[:paths].empty? || current_user.feature_flag_enabled?(:kb_semantic_api_migration, default: false)
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
