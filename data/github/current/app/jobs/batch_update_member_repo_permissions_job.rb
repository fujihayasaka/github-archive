# typed: true
# frozen_string_literal: true

class BatchUpdateMemberRepoPermissionsJob < ApplicationJob
  queue_as :update_member_repo_permissions

  MEMBER_UPDATE_BATCH_SIZE = 100

  # Updates org members and/or collaborators permissions/roles and deletes custom role if present and
  # has not dependencies
  #
  # user_roles        - Active records of user/permission or user/role association
  # action            - The permission to update to. Can be :read, :write, :admin, :triage, :maintain, or a custom role
  # organization      - Org object whose members and/or collaborators to be updated
  # role              - Custom role. default: nil
  # actor             - The user performing the action
  # context           - Hash of Strings with the users' previous Role {:old_permission, :old_base_role}
  #
  # Returns nothing
  def perform(user_roles, action:, organization:, role: nil, actor:, context: {})
    users = fetch_users(user_roles)
    repos = fetch_repos(user_roles)

    user_roles.each do |user_role|
      repo_id = user_role.try(:subject_id) || user_role.try(:target_id)
      repo = repos[repo_id]
      action = repo.evaluate_action(action)
      user = users[user_role.actor_id]

      with_write { repo.update_member(user, action: action.to_sym, actor: actor, context: context) }
      raise RuntimeError.new if repo.errors.any?
    end

    # only delete roles if all dependencies are updated
    if !role.nil? && role&.all_dependencies_updated?
      if with_write { role.destroy! }
        GitHub.dogstats.increment("orgs_roles.delete.queued_to_delete", tags: ["status:deleted"])
      end
    end
  end

  # Public: Batch update `batch_size` member's permission on this repository via background job.
  #
  # user_roles        - Member/collaborator whose permission we want to update.
  # action            - The permission to update to. Can be :read, :write, :admin, :triage, :maintain, or a custom role
  # role              - Custom role (default: nil)
  # batch_size        - Batch size to be passed processed.
  # organization      - Org object whose members and/or collaborators to be updated
  # context           - Hash of Strings with the users' previous Role {:old_permission, :old_base_role}
  #
  def self.batch_enqueue(user_roles:, action:, role: nil, organization:, actor:, context: {}, batch_size: MEMBER_UPDATE_BATCH_SIZE)
    user_roles.each_slice(batch_size) do |user_roles_slice|
      perform_later(user_roles_slice, action:, organization:, role:, actor:, context:)
    end
  end

  private

  def fetch_users(user_roles)
    return @users if defined?(@users)
    @users = User.where(id: user_roles.map(&:actor_id)).index_by(&:id)
  end

  def fetch_repos(user_roles)
    return @repos if defined?(@repos)
    repo_ids = []
    begin
      repo_ids = user_roles.map(&:subject_id)
    rescue NoMethodError
      repo_ids = user_roles.map(&:target_id)
    end
    @repos = Repository.where(id: repo_ids).index_by(&:id)
  end
end
