# typed: true
# frozen_string_literal: true

class MoveWork::ChooseResourcesForm
  include ActiveModel::Model

  attr_accessor :repository_ids, :project_ids

  validate :any_work_present
  validate :maximum_resources_selected

  MAXIMUM_RESOURCE_SELECTION = 50

  private

  def any_work_present
    return unless repository_ids.blank?
    return unless project_ids.blank?

    errors.add(:base, "You must select at least one work item to move")
  end

  def maximum_resources_selected
    errors.add(:base, "You can select a maximum of #{MAXIMUM_RESOURCE_SELECTION} projects") if project_ids.length > MAXIMUM_RESOURCE_SELECTION
    errors.add(:base, "You can select a maximum of #{MAXIMUM_RESOURCE_SELECTION} repositories") if repository_ids.length > MAXIMUM_RESOURCE_SELECTION
  end
end
