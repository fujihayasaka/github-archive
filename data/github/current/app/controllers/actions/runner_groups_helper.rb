# typed: false
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnerGroupsHelper
  extend ActiveSupport::Concern
  include Api::App::ActionsScientistHelper
  include Api::App::TwirpHelpers
  include Scientist

  MAX_RUNNER_GROUP_WORKFLOW_REFS_FULL_VALIDATION = 50

  private

  def runner_group_for(owner, id:)
    resp = get_runner_group(
      owner: owner,
      group_id: id,
      use_runner_admin: use_runner_admin?(owner),
      do_experiment: do_runner_admin_experiment?(owner),
    )

    resp&.value&.runner_group
  end

  # Gets a runner group by ID, or 404s if it doesn't exist.
  def get_runner_group_ensure_exists(owner, group_id)
    resp = handle_twirp_errors do
      get_runner_group(
        owner: owner,
        group_id: group_id,
        use_runner_admin: use_runner_admin?(owner),
        do_experiment: do_runner_admin_experiment?(owner),
      )
    end
    runner_group = resp&.runner_group
    deliver_error! 404 unless runner_group
    runner_group
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
    add_runner_group(
      actor: current_user,
      owner: owner,
      name: name,
      visibility: visibility,
      allow_public: allow_public,
      selected_targets: selected_targets,
      selected_workflow_refs: selected_workflow_refs,
      restricted_to_workflows: restricted_to_workflows,
      network_configuration_id: network_configuration_id,
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
    update_runner_group(
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
    delete_runner_group(
      actor: current_user,
      owner: owner,
      group_id: id
    )
  end

  def add_runners_for(owner, id:, runners_ids:)
    resp = add_runners_to_group(
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

    if entity.is_a?(Organization) && entity.feature_enabled?(:all_orgs_can_have_runner_groups)
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

  # The below methods were added to be shared with the API controllers
  # These are wrappers to the Launch::Twirp::RunnerGroupsClient methods
  OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

  sig { params(owner: OrgOrEnterprise, group_id: Integer, use_runner_admin: T::Boolean, include_runners: T::Boolean, include_hosted_runner_groups: T::Boolean, include_elastic_runners: T::Boolean, include_runner_scale_sets: T::Boolean, do_experiment: T::Boolean).returns(TwirpResponse) }
  def get_runner_group(owner:, group_id:, use_runner_admin:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false, do_experiment: false)
    if do_experiment
      science "long_running.actions.runner_groups.get_runner_group" do |e|
        e.use { get_runner_group(owner: owner, group_id: group_id, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: use_runner_admin, do_experiment: false) }
        e.try { get_runner_group(owner: owner, group_id: group_id, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: !use_runner_admin, do_experiment: false) }
        e.compare { |control, candidate| control&.status == candidate&.status && clean_runner_group(control&.value&.runner_group) == clean_runner_group(candidate&.value&.runner_group) }
        e.clean { |resp| clean_runner_group(resp&.value&.runner_group) }
      end
    end

    if use_runner_admin
      GitHub.build_runner_admin_client(owner).get_runner_group(
          owner: owner,
          group_id: group_id,
          include_runners: include_runners,
        )
    else
      Launch::Twirp.runner_groups_client.get_group(
          owner: owner,
          group_id: group_id,
          include_runners: include_runners,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_elastic_runners: include_elastic_runners,
          include_runner_scale_sets: include_runner_scale_sets
        )
    end
  end

  sig { params(owner: T.any(OrgOrEnterprise, Repository), use_runner_admin: T::Boolean, include_runners: T::Boolean, include_hosted_runner_groups: T::Boolean, include_elastic_runners: T::Boolean, include_runner_scale_sets: T::Boolean, do_experiment: T::Boolean).returns(TwirpResponse) }
  def list_runner_groups(owner:, use_runner_admin:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false, do_experiment: false)
    if do_experiment
      science "long_running.actions.runner_groups.list_runner_groups" do |e|
        e.use { list_runner_groups(owner: owner, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: use_runner_admin, do_experiment: false) }
        e.try { list_runner_groups(owner: owner, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: !use_runner_admin, do_experiment: false) }
        e.compare { |control, candidate| control&.status == candidate&.status && clean_runner_groups(control&.value&.runner_groups) == clean_runner_groups(candidate&.value&.runner_groups) }
        e.clean { |resp| clean_runner_groups(resp&.value&.runner_groups) }
      end
    end

    if use_runner_admin
      GitHub.build_runner_admin_client(owner).list_runner_groups(
          owner: owner,
          include_runners: include_runners,
          include_runner_scale_sets: include_runner_scale_sets
        )
    else
      Launch::Twirp.runner_groups_client.list_groups(
          owner: owner,
          include_runners: include_runners,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_elastic_runners: include_elastic_runners,
          include_runner_scale_sets: include_runner_scale_sets
        )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, name: String, runner_ids: T.nilable(T::Array[Integer]), visibility: T.nilable(Symbol), allow_public: T.nilable(T::Boolean), selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns(TwirpResponse) }
  def add_runner_group(actor:, owner:, name:, runner_ids: [], visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED, allow_public: false, selected_targets: [], selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).add_runner_group(
          actor: actor,
          owner: owner,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: selected_targets,
          allow_public: allow_public,
          restricted_to_workflows: restricted_to_workflows,
          selected_workflow_refs: selected_workflow_refs,
        )
    else
      Launch::Twirp.runner_groups_client.create_group(
          actor: actor,
          owner: owner,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: selected_targets,
          allow_public: allow_public,
          restricted_to_workflows: restricted_to_workflows,
          selected_workflow_refs: selected_workflow_refs,
        )
    end
  end

  sig { params(actor: User, owner: OrgOrEnterprise, group_id: Integer).returns(TwirpResponse) }
  def delete_runner_group(actor:, owner:, group_id:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).delete_runner_group(
        actor: actor,
        owner: owner,
        group_id: group_id
      )
    else
      Launch::Twirp.runner_groups_client.delete_group(
        actor: actor,
        owner: owner,
        group_id: group_id
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, name: T.nilable(String), visibility: T.nilable(Symbol), allow_public: T.nilable(T::Boolean), selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns(TwirpResponse) }
  def update_runner_group(actor:, owner:, group_id:, name:, visibility:, allow_public:, selected_targets: nil, selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).update_runner_group(
          actor: actor,
          owner: owner,
          group_id: group_id,
          name: name,
          visibility: visibility,
          allow_public: allow_public,
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
          network_configuration_id: network_configuration_id,
        )
    else
      Launch::Twirp.runner_groups_client.update_group(
          actor: actor,
          owner: owner,
          group_id: group_id,
          name: name,
          visibility: visibility,
          allow_public: allow_public,
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
          network_configuration_id: network_configuration_id,
        )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, runner_ids: T::Array[Integer]).returns(TwirpResponse) }
  def update_runners_in_group(actor:, owner:, group_id:, runner_ids:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).update_runners_in_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      )
    else
      Launch::Twirp.runner_groups_client.update_runners(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, runner_ids: T::Array[Integer]).returns(TwirpResponse) }
  def add_runners_to_group(actor:, owner:, group_id:, runner_ids:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).add_runners_to_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      )
    else
      Launch::Twirp.runner_groups_client.add_runners(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, runner_id: Integer).returns(TwirpResponse) }
  def remove_runner_from_group(actor:, owner:, group_id:, runner_id:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).remove_runner_from_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_id: runner_id
      )
    else
      Launch::Twirp.runner_groups_client.remove_runner(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_id: runner_id
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, selected_targets: T::Array[String]).returns(TwirpResponse) }
  def set_runner_group_permissions(actor:, owner:, group_id:, selected_targets:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).set_runner_group_permissions(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_targets: selected_targets
      )
    else
      Launch::Twirp.runner_groups_client.update_targets(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_targets: selected_targets
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, selected_target: String).returns(TwirpResponse) }
  def add_runner_group_permission(actor:, owner:, group_id:, selected_target:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).add_runner_group_permission(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      )
    else
      Launch::Twirp.runner_groups_client.add_target(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      )
    end
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, group_id: Integer, selected_target: String).returns(TwirpResponse) }
  def delete_runner_group_permission(actor:, owner:, group_id:, selected_target:)
    if use_runner_admin?(owner)
      GitHub.build_runner_admin_client(owner).delete_runner_group_permission(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      )
    else
      Launch::Twirp.runner_groups_client.remove_target(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      )
    end
  end

  sig { params(owner: T.any(Organization, Business, Repository, User)).returns(T::Boolean) }
  public def use_runner_admin?(owner)
    owner.feature_enabled?(:actions_runners_use_runner_admin_service)
  end

  # This module is included in Enterprise *and* Organization runnergroup controllers.
  # If this_business is defined, we can assume we're in the Enterprise context
  private def business_defined?
    defined?(this_business) && this_business.present?
  end

  sig { params(owner: T.any(Organization, Business, Repository, User), selected_workflow_refs: T.nilable(T::Array[String])).returns(T::Boolean) }
  public def use_syntax_only_workflow_validation?(owner, selected_workflow_refs)
    return false unless owner.feature_enabled?(:actions_runner_group_limit_workflow_refs_validation)
    return false unless selected_workflow_refs
    return false unless selected_workflow_refs.size > MAX_RUNNER_GROUP_WORKFLOW_REFS_FULL_VALIDATION
    true
  end
end
