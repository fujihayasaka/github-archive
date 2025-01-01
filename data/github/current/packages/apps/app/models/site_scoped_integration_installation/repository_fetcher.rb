# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  class RepositoryFetcher
    MAX_REPOSITORY_IDS = 1_000
    TOO_MANY_REPOSITORY_IDS_MSG = "Too many repositories for installation. Please supply up to #{MAX_REPOSITORY_IDS} repositories using the `repositories` or `repository_ids` request attributes"
    REPOSITORIES_NOT_CONSITENT_WITH_VISIBILITY_MSG = "There is at least one repository that does not match with given visibility."

    class Result
      class Error < StandardError; end

      def self.success(repositories) new(:success, repositories: repositories) end
      def self.failed(error) new(:failed, error: error) end

      attr_reader :error, :repositories

      def initialize(status, repositories: nil, error: nil)
        @status       = status
        @repositories = repositories
        @error        = error
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    # Returns repositories and error message while fetching
    def self.fetch(target, repository_ids: [], repository_names: [], visibility: nil)
      repositories = :all
      repository_ids = Set.new(repository_ids.map(&:to_i))

      if repository_names.present?
        found_repository_ids = target.repositories.where(name: repository_names).pluck(:id)
        if found_repository_ids.count != repository_names.uniq.count
          return Result.failed(SiteScopedIntegrationInstallation::Permissions::Result::HUMAN_READABLE_REASONS[:repositories_not_available_to_target])
        end
        repository_ids += found_repository_ids
      end

      if repository_ids.present?
        if repository_ids.count > MAX_REPOSITORY_IDS
          return Result.failed(TOO_MANY_REPOSITORY_IDS_MSG)
        end

        if visibility.present?
          if visibility == Repository::PUBLIC_VISIBILITY
            repositories = Repository.where(id: repository_ids.to_a, public: true)
          else
            internal_repository_ids = InternalRepository.where(repository_id: repository_ids.to_a).pluck(:repository_id)

            if visibility == Repository::INTERNAL_VISIBILITY
              repositories = Repository.where(id: internal_repository_ids, public: false)
            else
              private_repository_ids = repository_ids.to_a - internal_repository_ids
              repositories = Repository.where(id: private_repository_ids, public: false)
            end
          end

          if repositories.count != repository_ids.count
            return Result.failed(REPOSITORIES_NOT_CONSITENT_WITH_VISIBILITY_MSG)
          end
        else
          repositories = Repository.where(id: repository_ids.to_a)
        end
      end

      Result.success(repositories)
    end
  end
end
