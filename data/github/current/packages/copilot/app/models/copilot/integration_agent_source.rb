# typed: strict
# frozen_string_literal: true

module Copilot
  class IntegrationAgentSource < ApplicationRecord::Domain::Copilot
    self.table_name = "integration_agent_sources"
    self.strict_loading_by_default = true

    belongs_to :integration, strict_loading: false, inverse_of: :agent_source, optional: false

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain foreign_key: :repository_id, strict_loading: false

    validates :integration_id, uniqueness: true
    validates :repository_id, presence: true
    validates :commit_oid, presence: true
    validate  :validate_repository_and_commit_oid

    private

    sig { void }
    def validate_repository_and_commit_oid
      repo = repository
      return if repo.nil?

      # Validate repository is public (not private or internal)
      unless repo.public?
        errors.add(:repository_id, "must be a public repository")
        return
      end

      # Validate commit_oid exists in repository
      return if commit_oid.blank?

      ::Repositories.domain.commits.by_oid(repository: repo, commit_oid: commit_oid)
    rescue GitRPC::ObjectMissing, RepositoryObjectsCollection::InvalidObjectId
      errors.add(:commit_oid, "does not exist in the repository")
    end
  end
end
