# typed: false
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnerGroupsHelper
  extend ActiveSupport::Concern

  private

  def runner_group_for(owner, id:)
    resp = Launch::Twirp.runner_groups_client.get_group(
      owner: owner,
      group_id: id,
    )

    resp&.value&.runner_group
  end

  def create_group_for(
    owner,
    name:,
    visibility:,
    allow_public:,
    selected_targets: [],
    selected_workflow_refs: [],
    restricted_to_workflows: selected_workflow_refs.any?,
    network_configuration_id: nil
  )

    Launch::Twirp.runner_groups_client.create_group(
      actor: current_user,
      owner: owner,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_targets,
      selected_workflow_refs: selected_workflow_refs,
      restricted_to_workflows: restricted_to_workflows,
      network_configuration_id: network_configuration_id
    )
  end

  def update_group_for(
    owner,
    id:,
    name:,
    visibility:,
    allow_public:,
    selected_targets: [],
    selected_workflow_refs: [],
    restricted_to_workflows: selected_workflow_refs.any?,
    network_configuration_id: nil
  )

    Launch::Twirp.runner_groups_client.update_group(
      actor: current_user,
      owner: owner,
      group_id: id,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_targets,
      selected_workflow_refs: selected_workflow_refs,
      restricted_to_workflows: restricted_to_workflows,
      network_configuration_id: network_configuration_id
    )
  end

  def delete_group_for(owner, id:)
    Launch::Twirp.runner_groups_client.delete_group(
        actor: current_user,
        owner: owner,
        group_id: id,
      )
  end

  def add_runners_for(owner, id:, runners_ids:)
    resp = Launch::Twirp.runner_groups_client.add_runners(
      actor: current_user,
      owner: owner,
      group_id: id,
      runner_ids: runners_ids,
    )

    resp&.value&.runner_group
  end

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def restricted_plan_for_runner_groups?(entity)
    return false unless entity.is_a?(Organization)

    if GitHub.enterprise? || entity.plan.business_plus? || entity.plan.enterprise? || entity.plan.business?
      return false
    end

    true
  end

  def validate_selected_workflow_refs
    runner_group_id = params[:id]&.to_i

    @restricted_to_workflows = ActiveRecord::Type::Boolean.new.deserialize(params[:restricted_to_workflows])

    @selected_workflow_refs =
      params[:selected_workflow_refs]
        &.split(/,\s*/)
        &.map(&:strip)
        &.reject(&:empty?)
        &.uniq

    if @selected_workflow_refs.present?
      owner = business_defined? ? this_business : current_organization

      @selected_workflow_refs = @selected_workflow_refs.map do |raw_pattern|
        validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: owner).tap(&:validate)

        if validated_pattern.errors.any?
          flash[:error] = validated_pattern.errors.first.message
          redirect_to_runner_group_path(runner_group_id)
          return
        end
        validated_pattern.disambiguated_ref
      end
    end
  end

  private def redirect_to_runner_group_path(runner_group_id)
    if action_name == "update"
      redirect_to(
        if business_defined?
          settings_actions_runner_group_enterprise_path(id: runner_group_id)
        else
          settings_org_actions_runner_group_path(id: runner_group_id)
        end
      )
    elsif action_name == "create"
      redirect_to(
        if business_defined?
          settings_actions_add_runner_group_enterprise_path
        else
          settings_org_actions_runner_groups_path
        end
      )
    else
      raise "unknown action"
    end
  end

  def attach_network_configuration?(entity, network_config_id, runner_group_id, runner_group_name)
    return true if network_config_id == "-1" || network_config_id.empty?
    return false if runner_group_id.nil? || runner_group_name.empty?
    begin
      network_config_client.configure_compute_resource(entity, network_config_id, "actions", runner_group_id, runner_group_name)
      true
    rescue NetworkBundle::NetworkConfigurationsException => exception
      false
    end
  end

  def update_network_configuration?(entity, current_network_config_id, previous_network_config_id, runner_group_id, runner_group_name)

    # user did not select a network configuration, just change organization or workflow
    return true if current_network_config_id.empty? || (previous_network_config_id.empty? && current_network_config_id == "-1")

    if previous_network_config_id.empty?
      # no previous network configuration, configure the new network configuration
      begin
        network_config_client.configure_compute_resource(entity, current_network_config_id, "actions", runner_group_id, runner_group_name)
      rescue NetworkBundle::NetworkConfigurationsException => e
        return false
      end
      return true
    end

    if current_network_config_id == "-1"
      # user selected no network configuration, remove network configuration
      begin
        network_config_client.remove_network_configuration_from_runner_group(entity, previous_network_config_id, "actions", runner_group_id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        return false
      end
      return true
    end

    if current_network_config_id != previous_network_config_id
      # choose differnet network, reset and configure
      begin
        network_config_client.remove_network_configuration_from_runner_group(entity, previous_network_config_id, "actions", runner_group_id)
        network_config_client.configure_compute_resource(entity, current_network_config_id, "actions", runner_group_id, runner_group_name)
      rescue NetworkBundle::NetworkConfigurationsException => e
        return false
      end
      return true
    end
    true
  end

  # This module is included in Enterprise *and* Organization runnergroup controllers.
  # If this_business is defined, we can assume we're in the Enterprise context
  private def business_defined?
    defined?(this_business) && this_business.present?
  end
end
