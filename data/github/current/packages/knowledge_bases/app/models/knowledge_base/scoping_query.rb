# typed: true
# frozen_string_literal: true
class KnowledgeBase
  class ScopingQuery

    SourceRepo = T.type_alias do
      {
          id: Integer,
          ownerID: Integer,
          paths: T::Array[String]
      }
    end

    attr_reader :source_repos

    # Takes an array of source repos and turns them into the query we send to Blackbird
    sig { params(source_repos: T::Array[SourceRepo]).returns(String) }
    def self.from_source_repositories(source_repos:)
      new(source_repos:).build
    end

    def initialize(source_repos:)
      @source_repos = source_repos
    end

    sig { returns(String) }
    def build
      qualifiers = []
      source_repos.each do |source_repo|
        repo = Repositories::Public.find_active!(source_repo[:id])

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
