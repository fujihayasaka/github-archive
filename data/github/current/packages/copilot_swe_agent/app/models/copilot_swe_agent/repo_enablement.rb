# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class RepoEnablement < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Repositories::BelongsToRepository

    sig { returns(T.nilable(User)) }
    attr_accessor :actor

    self.table_name = "copilot_swe_agent_repo_enablements"
    self.strict_loading_by_default = true

    validates :owner_id, :repository_id, :enabled_by_id, presence: true

    after_commit :instrument_create, on: :create
    after_commit :instrument_destroy, on: :destroy

    belongs_to_repository_via_domain class_name: "::Repository", strict_loading: false
    belongs_to :owner, class_name: "::User", strict_loading: false
    belongs_to :enabled_by, class_name: "::User", strict_loading: false

    scope :for_repos_owned_by, -> (owner) { where(owner_id: owner.id) }

    sig { params(repository: Repository).returns(T::Boolean) }
    def self.enabled_for_repository?(repository)
      find_by(repository_id: repository.id, owner_id: repository.owner_id).present?
    end


    sig { params(repository_owner: T.any(Organization, User)).returns(T::Array[::Repository]) }
    def self.enabled_repositories_for_owner(repository_owner)
      ::Repositories::Public.active_owned_by(repository_owner.id).where(id: for_repos_owned_by(repository_owner).pluck(:repository_id)).to_a
    end

    sig { params(repository_ids: T::Array[Integer], owner: T.any(Organization, User), enabled_by: User).void }
    def self.enable_for_repositories!(repository_ids:, owner:, enabled_by:)
      # Nuke any enablement that wasn't provided in the new list so we can allow for de-selection
      for_repos_owned_by(owner).where.not(repository_id: repository_ids).includes(:repository).each do |enablement|
        next unless enablement.repository.adminable_by?(enabled_by)
        enablement.destroy_by(actor: enabled_by)
      end
      ::Repositories::Public.active_owned_by(owner.id).where(id: repository_ids).each do |repository|
        next unless repository.adminable_by?(enabled_by)
        find_or_create_by!(repository_id: repository.id, owner_id: owner.id) do |enablement|
          enablement.enabled_by_id = enabled_by.id
        end
      end
    end

    sig { params(actor: User).void }
    def destroy_by(actor:)
      @actor = actor
      destroy
    end

    private

    sig { void }
    def instrument_create
      Copilot::Instrumenter.instrument_swe_agent_enabled(self)
    end

    sig { void }
    def instrument_destroy
      Copilot::Instrumenter.instrument_swe_agent_disabled(self, actor: actor)
    end
  end
end
