# typed: false
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnerGroupsHelper
  extend ActiveSupport::Concern
  include Actions::RunnerGroupsClientHelper
  include Api::App::ActionsRunnerAdminHelper
  include Api::App::TwirpHelpers

  MAX_RUNNER_GROUP_WORKFLOW_REFS_FULL_VALIDATION = 50

  private

  def runner_group_for(owner, id:, is_ui_read: false, force_launch: false)
    resp = get_runner_group(
      owner: owner,
      group_id: id,
      use_runner_admin: !force_launch && use_runner_admin?(owner, is_ui_read: is_ui_read),
      do_experiment: do_runner_admin_experiment?(owner),
    )

    resp.value&.runner_group
  end

  # Gets a runner group by ID, or 404s if it doesn't exist.
  def get_runner_group_ensure_exists(owner, group_id, is_api_read: false)
    resp = handle_twirp_errors do
      get_runner_group(
        owner: owner,
        group_id: group_id,
        use_runner_admin: use_runner_admin?(owner, is_api_read: is_api_read),
        do_experiment: do_runner_admin_experiment?(owner),
      )
    end
    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group
    runner_group
  end

  sig { params(owner: OrgOrEnterprise, name: String, visibility: Symbol, allow_public: T::Boolean, selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns([TwirpResponse, String]) }
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
    add_runner_group(
      actor: current_user,
      owner: owner,
      use_runner_admin: use_runner_admin?(owner, is_write: true),
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_targets,
      selected_workflow_refs: selected_workflow_refs,
      restricted_to_workflows: restricted_to_workflows,
      network_configuration_id: network_configuration_id,
    )
  end

  sig { params(owner: OrgOrEnterprise, id: Integer, name: T.nilable(String), visibility: T.nilable(Symbol), allow_public: T.nilable(T::Boolean), selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns([TwirpResponse, String]) }
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
    update_runner_group(
      actor: current_user,
      owner: owner,
      use_runner_admin: use_runner_admin?(owner, is_write: true),
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

  sig { params(owner: OrgOrEnterprise, id: Integer).returns([TwirpResponse, String]) }
  def delete_group_for(owner, id:)
    delete_runner_group(
      actor: current_user,
      owner: owner,
      use_runner_admin: use_runner_admin?(owner, is_write: true),
      group_id: id
    )
  end

  sig { params(owner: OrgOrEnterprise, id: Integer, runners_ids: T::Array[Integer]).returns([TwirpResponse, String]) }
  def add_runners_for(owner, id:, runners_ids:)
    add_runners_to_group(
      actor: current_user,
      owner: owner,
      use_runner_admin: use_runner_admin?(owner, is_write: true),
      group_id: id,
      runner_ids: runners_ids,
    )
  end

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def restricted_plan_for_runner_groups?(entity)
    return false unless entity.is_a?(Organization)

    if GitHub.enterprise? || entity.plan.business_plus? || entity.plan.enterprise? || entity.plan.business?
      return false
    end

    if entity.is_a?(Organization) && entity.feature_flag_enabled?(:all_orgs_can_have_runner_groups, default: true)
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

      syntax_only_validation = use_syntax_only_workflow_validation?(owner, @selected_workflow_refs)
      @selected_workflow_refs = @selected_workflow_refs.map do |raw_pattern|
        validated_pattern = Actions::WorkflowPattern.new(raw_pattern, owner: owner, syntax_only_validation: syntax_only_validation).tap(&:validate)

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
      Kernel.raise "unknown action"
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

  sig { params(owner: T.any(Organization, Business, Repository, User), selected_workflow_refs: T.nilable(T::Array[String])).returns(T::Boolean) }
  public def use_syntax_only_workflow_validation?(owner, selected_workflow_refs)
    return false unless owner.feature_flag_enabled?(:actions_runner_group_limit_workflow_refs_validation, default: true)
    return false unless selected_workflow_refs
    return false unless selected_workflow_refs.size > MAX_RUNNER_GROUP_WORKFLOW_REFS_FULL_VALIDATION
    true
  end
end
