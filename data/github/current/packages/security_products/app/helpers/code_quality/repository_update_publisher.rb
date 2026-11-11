# typed: strict
# frozen_string_literal: true

module CodeQuality
  class RepositoryUpdatePublisher
    extend T::Helpers

    # Publishes a code_quality.v0.RepositoryUpdate event to Hydro.
    sig { params(repo: Repository, code_quality_enabled: T.nilable(T::Boolean)).void }
    def self.publish_repository(repo:, code_quality_enabled: nil)
      GitHub.hydro_publisher.publish(
        {
          repository_id: repo.id,
          repository_name: repo.name,
          owner_id: repo.owner_id,
          is_archived: repo.archived?,
          code_quality_enabled:,
          is_deleted: repo.deleted?,
          visibility: visibility_for(repo),
          customer_id: resolve_customer_id(repo),
        },
        schema: "code_quality.v0.RepositoryUpdate",
        topic: "code_quality.v0.RepositoryUpdate",
        partition_key: repo.id
      )
    end

    # Publishes a code_quality.v0.RepositoryUpdate event to Hydro for a deleted repository.
    sig { params(repository_id: Integer).void }
    def self.publish_deleted_repository(repository_id:)
      GitHub.hydro_publisher.publish(
        {
          repository_id:,
          is_deleted: true,
        },
        schema: "code_quality.v0.RepositoryUpdate",
        topic: "code_quality.v0.RepositoryUpdate",
        partition_key: repository_id
      )
    end

    # Attempts to load the repository by ID and publishes a code_quality.v0.RepositoryUpdate event to Hydro.
    sig { params(repository_id: Integer).void }
    def self.publish_repository_id(repository_id:)
      # Use get_active_or_deleted to include soft-deleted repositories.
      repo = Repositories::Public.get_active_or_deleted(repository_id)
      if repo.nil?
        # Hard-purged from DB
        publish_deleted_repository(repository_id:)
      else
        # Works for both active and soft-deleted repos.
        publish_repository(repo:)
      end
    end

    sig { params(repo: Repository).returns(Symbol) }
    def self.visibility_for(repo)
      case repo.visibility
      when Repository::PUBLIC_VISIBILITY
        :PUBLIC
      when Repository::INTERNAL_VISIBILITY
        :INTERNAL
      else
        :PRIVATE
      end
    end

    sig { params(repo: Repository).returns(T.nilable(Integer)) }
    def self.resolve_customer_id(repo)
      Licensing::Customer.id_for(repo)
    end
  end
end
