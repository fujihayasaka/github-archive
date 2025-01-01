# typed: true
# frozen_string_literal: true

# Provides an interface to manage abilities for all Advisories
# & their Workspaces belonging to a given Repository#id
class Repository::AdvisoryAbilityManager
  include GitHub::Memoizer

  def initialize(repository_id)
    @repository_id = repository_id
  end

  def self.grant(actor, repository:, action:)
    if action == :admin
      new(repository.id).grant_all_workspaces(actor, action: :admin)
    else
      # In the event the actor is being granted :read or :write, we should
      # revoke inherited abilities on workspaces for which they are not
      # explicit advisory collaborators, and reduce abilities from :admin
      # to :write on workspaces where they are advisory collaborators.
      new(repository.id).revoke_or_grant_collaborator_workspaces(actor)
    end
  end

  def self.revoke(subject, repository:, actor: nil)
    new(repository.id).revoke_all_advisories(subject, actor: actor)
  end

  def self.transfer_ownership(repository:)
    new(repository.id).transfer_ownership
  end

  def self.change_visibility(repository:)
    new(repository.id).revoke_inaccessible_advisories
  end

  def self.hide_and_remove_all(actor, repository:)
    new(repository.id).hide_and_remove_all_workspaces(actor)
  end

  def self.remove_collaborators_from_organizations(collabs:, organizations:)
    return if organizations.empty? || collabs.empty?

    indexed_collabs = collabs.index_by(&:id)
    collab_ids = indexed_collabs.keys
    adv_collabs_map = {}

    Ability.where(actor_id: collab_ids).where(
      actor_type: "User",
      subject_type: "RepositoryAdvisory",
      priority: Ability.priorities[:direct],
    ).distinct
    .pluck(:actor_id, :subject_id).each do |actor_id, repo_adv_id|
      adv_collabs_map[repo_adv_id] = Array(adv_collabs_map[repo_adv_id]) << actor_id
    end
    return if adv_collabs_map.empty?

    advisories = RepositoryAdvisory.where(id: adv_collabs_map.keys)
    repository_ids = advisories.pluck(:repository_id)

    # select only repositories that are in the organizations
    indexed_org_repos = Repository.where(id: repository_ids, organization_id: organizations.pluck(:id)).index_by(&:id)

    # select only advisories that are in the organizations
    advisories = advisories.where(repository_id: indexed_org_repos.keys)
    advisories.each do |advisory|
      adv_collabs_map[advisory.id].each do |collab_id|
        advisory.remove_collaborator(indexed_collabs[collab_id], actor: indexed_org_repos[advisory.repository_id].owner)
      end
    end
  end

  # Grants abilities on all Advisory Workspaces
  def grant_all_workspaces(actor, action:)
    return if repository_is_workspace?(@repository_id)

    workspaces.map do |workspace|
      grant_workspace(actor, workspace, action: action)
    end
  end

  # Revokes abilities on all Advisories & their workspaces
  def revoke_all_advisories(subject, actor: nil)
    return if repository_is_workspace?(@repository_id)

    advisories.map do |advisory|
      advisory.remove_collaborator(subject, actor: actor)
    end
  end

  def revoke_inaccessible_advisories
    actors = Set.new
    advisories.each do |advisory|
      actors += Authorization.service.direct_abilities_on_subject(subject: advisory).map(&:actor)
    end

    Promise.all(
      actors.map do |actor|
        repository.async_readable_by?(actor).then do |readable|
          revoke_all_advisories(actor) unless readable
        end
      end
    ).sync
  end

  # Revokes abilities on workspaces where actor is not an advisory collaborator,
  # and grants write abilities on workspaces where actor is an advisory collaborator.
  def revoke_or_grant_collaborator_workspaces(actor)
    return if repository_is_workspace?(@repository_id)

    workspaces.map do |workspace|
      ability = Authorization.service.direct_ability_between(actor: actor, subject: workspace.parent_advisory)

      if ability&.action == "write"
        grant_workspace(actor, workspace, action: :write)
      else
        revoke_workspace(actor, workspace)
      end
    end
  end

  # Enqueues a job to change ownership of every workspace owned by @repository
  #
  # This is intended to be called from a background job in order to fan out
  # a single transfer job per workspace for atomicity.
  def transfer_ownership
    return if repository_is_workspace?(@repository_id)

    workspaces.pluck(:id).map do |workspace_repository_id|
      TransferWorkspaceJob.perform_later(workspace_repository_id)
    end
  end

  # Performs workspace removal by synchronously hiding it and enqueuing
  # the normal delete job to complete archival.
  def hide_and_remove_all_workspaces(actor)
    return if repository_is_workspace?(@repository_id)

    workspaces.map do |workspace_repository|
      # Remove workspaces, but don't count instrument them as deletions
      workspace_repository.remove(actor, instrument: false)
    end
  end

  private

  memoize def repository
    Repositories::Public.get_active_or_deleted!(@repository_id)
  end

  memoize def advisories
    RepositoryAdvisory.where(repository_id: @repository_id)
  end

  memoize def workspaces
    Repository.where(id: advisories.pluck(:workspace_repository_id))
  end

  def repository_is_workspace?(repository_id)
    RepositoryAdvisory.where(workspace_repository_id: repository_id).any?
  end

  def grant_workspace(actor, workspace, action:)
    if actor.is_a? Team
      workspace.add_team(actor, action: action)
    elsif workspace.member?(actor) || action == :admin
      workspace.add_member(actor, action: action)
    else
      repository_invitation = RepositoryInvitation.find_by(invitee_id: actor.id, repository_id: workspace.id)
      repository_invitation.set_permissions(action, repository_invitation.inviter) if repository_invitation
    end
  end

  def revoke_workspace(actor, workspace)
    if actor.is_a? Team
      workspace.remove_team(actor)
    else
      workspace.remove_vulnerability_reporter(actor)
      workspace.remove_member(actor)
      repository_invitation = RepositoryInvitation.find_by(invitee_id: actor.id, repository_id: workspace.id)
      repository_invitation.cancel!(actor: repository_invitation.inviter, force: true) if repository_invitation
    end
  end
end
