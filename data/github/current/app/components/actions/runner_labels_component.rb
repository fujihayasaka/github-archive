# typed: true
# frozen_string_literal: true

class Actions::RunnerLabelsComponent < ApplicationComponent
  attr_reader :labels

  def initialize(owner:, runner_ids:, labels:, selected_labels:, descriptor: nil, form_id: nil)
    @owner = owner
    @runner_ids = runner_ids
    @labels = labels
    @selected_labels = selected_labels || []
    @runner_count = runner_ids.length
    @descriptor = descriptor
    @form_id = form_id
  end

  def selected?(label)
    selected_labels.count(label.id) == @runner_count
  end

  def partially_selected?(label)
    selected_labels.include?(label.id)
  end

  def create_label_path
    if business_owner?
      settings_actions_create_runner_label_enterprise_path(owner, form_id: @form_id)
    elsif org_owner?
      create_org_runner_label_path(owner, form_id: @form_id)
    else
      create_repo_runner_label_path(user_id: owner.owner_display_login, repository: owner, form_id: @form_id)
    end
  end

  def update_label_path
    return nil if runner_ids.length == 0
    runner_id = runner_ids.first

    if business_owner?
      settings_actions_update_runner_labels_enterprise_path(owner, runner_id: runner_id)
    elsif org_owner?
      update_org_runner_labels_path(owner, runner_id: runner_id)
    else
      update_repo_runner_label_path(user_id: owner.owner_display_login, repository: owner, runner_id: runner_id)
    end
  end

  #unique id for this menu. Will use the runner id if none is provided
  def descriptor
    @descriptor || runner_ids.first
  end

  private

  attr_reader :owner, :runner_ids

  def business_owner?
    owner.is_a?(Business)
  end

  def org_owner?
    owner.is_a?(Organization)
  end

  def selected_labels
    @selected_labels.map(&:to_i)
  end
end
