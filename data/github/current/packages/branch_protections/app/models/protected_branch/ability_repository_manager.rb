# typed: true
# frozen_string_literal: true

class ProtectedBranch::AbilityRepositoryManager
  def initialize(repository_id)
    @repository_id = repository_id
  end

  # Public: Revoke actors access to the repos protected branches
  #
  # actor       - user or team who has access to the protected branch
  # repository  - repository with protected branches
  def self.revoke(actor, repository:)
    new(repository.id).revoke_all_protected_branches(actor)
  end

  # Revokes abilities on all Protected Branches
  def revoke_all_protected_branches(actor)
    abilities = Ability
                       .where(actor_type: actor.class.name,
                              actor_id: actor.id,
                              subject_type: "ProtectedBranch",
                              subject_id: protected_branch_ids)
    Ability.revoke_abilities(abilities)
  end

  private

  def protected_branch_ids
    ProtectedBranch.where(repository_id: @repository_id).pluck(:id)
  end
end
