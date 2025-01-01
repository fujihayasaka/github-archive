# typed: strict
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

# These are client wrappers to the Launch::Twirp::RunnerGroupsClient methods
module Actions::RunnerGroupsClientHelper
  include Api::App::ActionsRunnerAdminHelper
  include Api::App::ActionsScientistHelper

  WRITTEN_TO_LAUNCH = "launch"
  WRITTEN_TO_RUNNER_ADMIN = "runner-admin"

  private

  OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

  sig { params(owner: T.any(Organization, Business, Repository), params: ActionController::Parameters).returns(T::Boolean) }
  def should_force_launch?(owner:, params:)
    params[:written_to] == WRITTEN_TO_LAUNCH
  end

  sig { params(owner: OrgOrEnterprise, group_id: Integer, use_runner_admin: T::Boolean, include_runners: T::Boolean, include_hosted_runner_groups: T::Boolean, include_elastic_runners: T::Boolean, include_runner_scale_sets: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def get_runner_group(owner:, group_id:, use_runner_admin:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false, do_experiment: false, runner_admin_can_read_override: false)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).get_runner_group(
          owner: owner,
          group_id: group_id,
          include_runners: include_runners,
          can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
        )

      # If the group is not found in Runner Admin (should be because it is hosted), fall back to Launch
      if !resp.value&.runner_group
        launch_resp = Launch::Twirp.runner_groups_client.get_group(
          owner: owner,
          group_id: group_id,
          include_runners: include_runners,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_elastic_runners: include_elastic_runners,
          include_runner_scale_sets: include_runner_scale_sets
        )

        # If the group is hosted, return the Launch response
        if launch_resp.value&.runner_group&.is_hosted
          resp = launch_resp
        end
      end
    else
      resp = Launch::Twirp.runner_groups_client.get_group(
          owner: owner,
          group_id: group_id,
          include_runners: include_runners,
          include_hosted_runner_groups: include_hosted_runner_groups,
          include_elastic_runners: include_elastic_runners,
          include_runner_scale_sets: include_runner_scale_sets
        )
    end

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner_groups.get_runner_group",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { get_runner_group(owner: owner, group_id: group_id, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: false) },
        runner_admin_override_func: -> { get_runner_group(owner: owner, group_id: group_id, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: true, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runner_group(control&.value&.runner_group) == clean_runner_group(candidate&.value&.runner_group) },
        clean_func: ->(resp) { clean_runner_group(resp&.value&.runner_group) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = get_runner_group(owner: owner, group_id: group_id, include_runners: include_runners, include_hosted_runner_groups: include_hosted_runner_groups, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: false)
    end

    resp
  end

  sig { params(owner: T.any(OrgOrEnterprise, Repository), use_runner_admin: T::Boolean, include_runners: T::Boolean, include_elastic_runners: T::Boolean, include_runner_scale_sets: T::Boolean, do_experiment: T::Boolean, runner_admin_can_read_override: T::Boolean).returns(TwirpResponse) }
  def list_runner_groups(owner:, use_runner_admin:, include_runners: false, include_elastic_runners: false, include_runner_scale_sets: false, do_experiment: false, runner_admin_can_read_override: false)
    if use_runner_admin
      resp = GitHub.build_runner_admin_client(owner).list_runner_groups(
        owner: owner,
        include_runners: include_runners,
        include_runner_scale_sets: include_runner_scale_sets,
        can_read_override: runner_admin_can_read_override || owner.feature_flag_enabled?(:actions_runners_use_runner_admin_service, default: false)
      )
    else
      owner = T.let(owner, T.untyped)
      resp = Launch::Twirp.runner_groups_client.list_groups(
        owner: owner,
        include_runners: include_runners,
        include_hosted_runner_groups: false,
        include_elastic_runners: include_elastic_runners,
        include_runner_scale_sets: include_runner_scale_sets
      )
    end

    resp.value&.runner_groups ||= []
    resp.value&.runner_groups&.reject! { |group| group["is_hosted"] }

    if do_experiment
      resp = do_experiment_with_fallbacks(
        experiment_name: "long_running.actions.runner_groups.list_runner_groups",
        original_response: resp,
        use_runner_admin: use_runner_admin,
        owner: owner,
        launch_func: -> { list_runner_groups(owner: owner, include_runners: include_runners, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: false) },
        runner_admin_override_func: -> { list_runner_groups(owner: owner, include_runners: include_runners, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: true, runner_admin_can_read_override: true) },
        compare_func: ->(control, candidate) { control&.status == candidate&.status && clean_runner_groups(control&.value&.runner_groups) == clean_runner_groups(candidate&.value&.runner_groups) },
        clean_func: ->(resp) { clean_runner_groups(resp&.value&.runner_groups) }
      )
    elsif use_runner_admin && resp.status == 403 && !runner_admin_can_read_override
      # Call to runner admin is not authorized, so fall back to Launch
      resp = list_runner_groups(owner: owner, include_runners: include_runners, include_elastic_runners: include_elastic_runners, include_runner_scale_sets: include_runner_scale_sets, use_runner_admin: false)
    end

    resp
  end

  sig { params(owner: T.any(Organization, Business), include_runners: T::Boolean).returns(TwirpResponse) }
  def get_hosted_runner_group(owner:, include_runners: false)
    resp = Launch::Twirp.runner_groups_client.list_groups(
      owner: owner,
      include_runners: include_runners,
      include_hosted_runner_groups: true,
      include_elastic_runners: false,
      include_runner_scale_sets: false
    )

    resp.value&.runner_groups&.select! { |group| group["is_hosted"] }
    resp
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, name: String, runner_ids: T.nilable(T::Array[Integer]), visibility: T.nilable(Symbol), allow_public: T.nilable(T::Boolean), selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns([TwirpResponse, String]) }
  def add_runner_group(actor:, owner:, use_runner_admin:, name:, runner_ids: [], visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED, allow_public: false, selected_targets: [], selected_workflow_refs: [], restricted_to_workflows: !selected_workflow_refs.nil? && selected_workflow_refs.any?, network_configuration_id: nil)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).add_runner_group(
          actor: actor,
          owner: owner,
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          selected_targets: selected_targets,
          allow_public: allow_public,
          restricted_to_workflows: restricted_to_workflows,
          selected_workflow_refs: selected_workflow_refs,
        ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.create_group(
      actor: actor,
      owner: owner,
      name: name,
      runner_ids: runner_ids,
      visibility: visibility,
      selected_targets: selected_targets,
      allow_public: allow_public,
      restricted_to_workflows: restricted_to_workflows,
      selected_workflow_refs: selected_workflow_refs,
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: User, owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer).returns([TwirpResponse, String]) }
  def delete_runner_group(actor:, owner:, use_runner_admin:, group_id:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).delete_runner_group(
        actor: actor,
        owner: owner,
        group_id: group_id
      ), WRITTEN_TO_RUNNER_ADMIN]

      # If the call was not authorized, fall back to Launch
      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.delete_group(
      actor: actor,
      owner: owner,
      group_id: group_id
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, name: T.nilable(String), visibility: T.nilable(Symbol), allow_public: T.nilable(T::Boolean), selected_targets: T.nilable(T::Array[String]), selected_workflow_refs: T.nilable(T::Array[String]), restricted_to_workflows: T.nilable(T::Boolean), network_configuration_id: T.nilable(String)).returns([TwirpResponse, String]) }
  def update_runner_group(actor:, owner:, use_runner_admin:, group_id:, name:, visibility:, allow_public:, selected_targets: nil, selected_workflow_refs: [], restricted_to_workflows: !selected_workflow_refs.nil? && selected_workflow_refs.any?, network_configuration_id: nil)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).update_runner_group(
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
        ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.update_group(
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
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, runner_ids: T::Array[Integer]).returns([TwirpResponse, String]) }
  def update_runners_in_group(actor:, owner:, use_runner_admin:, group_id:, runner_ids:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).update_runners_in_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.update_runners(
      actor: actor,
      owner: owner,
      group_id: group_id,
      runner_ids: runner_ids,
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, runner_ids: T::Array[Integer]).returns([TwirpResponse, String]) }
  def add_runners_to_group(actor:, owner:, use_runner_admin:, group_id:, runner_ids:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).add_runners_to_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_ids: runner_ids,
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.add_runners(
      actor: actor,
      owner: owner,
      group_id: group_id,
      runner_ids: runner_ids,
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, runner_id: Integer).returns([TwirpResponse, String]) }
  def remove_runner_from_group(actor:, owner:, use_runner_admin:, group_id:, runner_id:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).remove_runner_from_group(
        actor: actor,
        owner: owner,
        group_id: group_id,
        runner_id: runner_id
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.remove_runner(
      actor: actor,
      owner: owner,
      group_id: group_id,
      runner_id: runner_id
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, selected_targets: T::Array[String]).returns([TwirpResponse, String]) }
  def set_runner_group_permissions(actor:, owner:, use_runner_admin:, group_id:, selected_targets:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).set_runner_group_permissions(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_targets: selected_targets
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.update_targets(
      actor: actor,
      owner: owner,
      group_id: group_id,
      selected_targets: selected_targets
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, selected_target: String).returns([TwirpResponse, String]) }
  def add_runner_group_permission(actor:, owner:, use_runner_admin:, group_id:, selected_target:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).add_runner_group_permission(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.add_target(
      actor: actor,
      owner: owner,
      group_id: group_id,
      selected_target: selected_target
    ), WRITTEN_TO_LAUNCH]
  end

  sig { params(actor: T.nilable(User), owner: OrgOrEnterprise, use_runner_admin: T::Boolean, group_id: Integer, selected_target: String).returns([TwirpResponse, String]) }
  def delete_runner_group_permission(actor:, owner:, use_runner_admin:, group_id:, selected_target:)
    if use_runner_admin
      resp = [GitHub.build_runner_admin_client(owner).delete_runner_group_permission(
        actor: actor,
        owner: owner,
        group_id: group_id,
        selected_target: selected_target
      ), WRITTEN_TO_RUNNER_ADMIN]

      return resp if resp[0].status != 403
    end

    [Launch::Twirp.runner_groups_client.remove_target(
      actor: actor,
      owner: owner,
      group_id: group_id,
      selected_target: selected_target
    ), WRITTEN_TO_LAUNCH]
  end
end
