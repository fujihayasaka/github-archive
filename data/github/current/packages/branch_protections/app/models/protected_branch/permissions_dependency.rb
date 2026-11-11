# typed: true
# frozen_string_literal: true

module ProtectedBranch::PermissionsDependency
  extend T::Helpers

  requires_ancestor { ProtectedBranch }

  def authorized?(actor)
    return true unless has_authorized_actors?

    @is_authorized ||= {}
    @is_authorized.fetch(actor) do
      write_deploy_key?(actor) ||
      authorized_actor?(actor)
    end
  end

  def push_authorized?(actor)
    repository_writable_by?(actor) && authorized?(actor)
  end

  def repository_writable_by?(actor)
    # resources.contents.writable_by? doesn't work for child teams/child team
    # members so fall by back to method that checks child teams
    T.must(repository).resources.contents.writable_by?(actor) ||
      T.must(repository).resources.single_file.writable_by?(actor) ||
      T.must(repository).writable_by?(actor, include_child_teams: true)
  end

  # actor - User, Bot or PublicKey
  #
  # returns false if the actor isn't authorized by any authzd policy
  # returns true if the actor is authorized by an authzd policy
  def authorized_actor?(actor)
    # The merge queue uses a bot to merge changes. It should always be authorized
    if merge_queue_enabled? && authorized_actors_only? && actor == GitHub.merge_queue_bot
      return true
    end

    ::Permissions::Enforcer.authorize(
      action: :push_protected_branch,
      actor: actor,
      subject: self,
    ).allow?
  end
end
