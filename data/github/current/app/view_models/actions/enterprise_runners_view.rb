# typed: true
# frozen_string_literal: true

class Actions::EnterpriseRunnersView < Actions::RunnersView
  def show_labels?
    true
  end

  def settings_owner_type
    "enterprise"
  end

  def can_manage_runners?
    true
  end

  def add_runner_path
    urls.settings_actions_add_runner_enterprise_path(settings_owner)
  end

  def add_larger_runner_path(runner_group_id: nil)
    urls.settings_actions_add_larger_runner_enterprise_path(settings_owner, runner_group_id: runner_group_id)
  end

  def runner_details_path(id:)
    urls.settings_actions_runner_details_enterprise_path(settings_owner, id: id)
  end

  def runner_scale_set_details_path(id:)
    urls.settings_actions_runner_scale_set_enterprise_path(settings_owner, id: id)
  end

  def larger_runner_details_path(id:, viewing_from_runner_group: false)
    urls.settings_actions_larger_runner_details_enterprise_path(settings_owner, id: id, viewing_from_runner_group: viewing_from_runner_group)
  end

  def delete_runner_path(id:, os:)
    urls.settings_actions_delete_runner_modal_enterprise_path(settings_owner, id: id, os: os)
  end

  def force_remove_runner_path(id:)
    urls.settings_actions_delete_runner_enterprise_path(settings_owner, id: id)
  end

  def runners_path
    "" # Not implemented yet
  end

  def labels_path(runner_id:, selected_labels:, form_id: nil)
    urls.settings_actions_runner_labels_enterprise_path(settings_owner, runner_id: runner_id, applied_labels: selected_labels, form_id: form_id)
  end

  def create_runner_group_path
    urls.settings_actions_create_runner_group_enterprise_path(settings_owner)
  end

  def update_runner_group_path(id:)
    urls.settings_actions_update_runner_group_enterprise_path(settings_owner, id: id)
  end

  def delete_runner_group_path(id:)
    urls.settings_actions_delete_runner_group_enterprise_path(settings_owner, id: id)
  end

  def runner_group_targets_path(id: nil)
    urls.settings_actions_runner_group_targets_enterprise_path(settings_owner, id: id)
  end

  def update_runner_group_runners_path
    urls.settings_actions_update_runner_group_runners_enterprise_path(settings_owner)
  end

  def runner_groups_menu_path
    urls.settings_actions_runner_groups_menu_enterprise_path(settings_owner)
  end

  def update_runner_path(id:, viewing_from_runner_group: false)
    urls.settings_actions_update_runner_enterprise_path(settings_owner, id: id)
  end

  def hosted_runners_path(business)
    urls.settings_actions_hosted_runners_enterprise_path(business)
  end

  def delete_larger_runner_path(id, viewing_from_runner_group: false)
    urls.settings_actions_delete_larger_runner_enterprise_path(settings_owner, id: id, viewing_from_runner_group: viewing_from_runner_group)
  end

  def runner_scoped_to_view?(runner)
    # All the runners returned for an enterprise will be scoped to the enterprise. Org and repo level runners are not displayed at the enterprise level.
    true
  end

  def check_name_path
    urls.settings_actions_check_name_larger_runner_enterprise_path(settings_owner)
  end

  def runner_custom_image_path(id:)
    urls.settings_actions_custom_image_versions_enterprise_path(settings_owner, image_id: id)
  end
end
