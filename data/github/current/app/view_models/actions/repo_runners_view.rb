# typed: true
# frozen_string_literal: true

class Actions::RepoRunnersView < Actions::RunnersView
  def show_labels?
    true
  end

  def can_manage_runners?
    !unverified_or_spammy_user?
  end

  def self_hosted_runners_disabled_by_admin?
    settings_owner.repo_self_hosted_runners_disabled_by_owner?
  end

  def add_runner_path
    urls.repository_actions_settings_add_new_runner_path(repo_params)
  end

  def delete_runner_path(id:, os:)
    urls.repository_actions_settings_delete_runner_modal_path(
      repo_params.merge(id: id, os: os)
    )
  end

  def runners_path
    urls.repository_actions_settings_list_runners_path(repo_params)
  end

  def runner_details_path(id:)
    urls.repository_actions_settings_runner_details_path(repo_params.merge(id: id))
  end

  def runner_scale_set_details_path(id:)
    urls.settings_repo_actions_runner_scale_set_path(repo_params.merge(id: id))
  end

  def labels_path(runner_id:, selected_labels:, form_id: nil)
    urls.repo_runner_labels_path(repo_params.merge(runner_id: runner_id, applied_labels: selected_labels, form_id: form_id))
  end

  def runner_scoped_to_view?(runner)
    # `inherited?` only returns true for enterprise-level runners that are accessed from the org or repo level.
    # Repos have their own default group. Runners created at the repo level can only be created in the repo's default group.
    !runner.is_a?(Actions::LargerRunner) && runner.is_in_default_group?
  end

  private

  def unverified_or_spammy_user?
    current_user.spammy? ||
      settings_owner.owner.spammy? ||
      current_user.should_verify_email?
  end

  def repo_params
    {
      user_id: settings_owner.owner_display_login,
      repository: settings_owner,
    }
  end
end
