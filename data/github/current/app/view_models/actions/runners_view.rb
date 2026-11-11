# typed: true
# frozen_string_literal: true

class Actions::RunnersView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :settings_owner  # Repository or Owner

  def settings_owner_type
    settings_owner.class.name.downcase
  end

  def show_labels?
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def can_manage_runners?
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def self_hosted_runners_disabled_by_admin?
    false
  end

  def add_runner_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def runner_details_path(id:)
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def larger_runner_details_path(id:)
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def add_larger_runner_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def delete_runner_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def force_remove_runner_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def runners_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def labels_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def create_runner_group_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def update_runner_group_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def delete_runner_group_path(id:)
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def runner_group_targets_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def update_runner_group_runners_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def runner_groups_menu_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def billing_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def update_runner_path(id:)
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def hosted_runners_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  def delete_larger_runner_path
    raise NotImplementedError, "needs to be implemented by subclass"
  end
end
