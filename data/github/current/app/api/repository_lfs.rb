# typed: true
# frozen_string_literal: true

class Api::RepositoryLfs < Api::App
  include ReceiveSchemaWithOpenApi

  # Enable Git LFS for a repository
  put "/repositories/:repository_id/lfs", operation_id: "repos/enable-lfs-for-repo" do
    control_access :manage_lfs_for_repo,
      resource: repo = find_repo!,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    # Enable LFS for the repo
    if !GitHub.git_lfs_config_enabled?
      deliver_error! 403, message: "Git LFS support not enabled because Git LFS is globally disabled."
    elsif !repo.network_root? && repo.root && !repo.root.git_lfs_enabled?
      deliver_error! 403, message: "Git LFS support not enabled because Git LFS is disabled for the root repository in the network."
    elsif !repo.owner.git_lfs_enabled?
      deliver_error! 403, message: "Git LFS support not enabled because Git LFS is disabled for #{repo.owner.login_for_api}."
    else
      repo.enable_git_lfs(current_user)
      deliver_empty status: 202
    end
  end

  # Disable Git LFS for a repository
  delete "/repositories/:repository_id/lfs", operation_id: "repos/disable-lfs-for-repo" do
    control_access :manage_lfs_for_repo,
      resource: repo = find_repo!,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    # Disable LFS for the repo
    repo.disable_git_lfs(current_user)
    deliver_empty status: 204
  end
end
