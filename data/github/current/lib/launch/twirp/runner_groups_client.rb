# typed: true
# frozen_string_literal: true

module Launch
  module Twirp
    class RunnerGroupsClient < Launch::Twirp::BaseClient

      OrgOrEnterprise = T.type_alias { T.any(Organization, Business) }

      GROUP_VISIBILITY_ALL = :ALL
      GROUP_VISIBILITY_SELECTED = :SELECTED
      GROUP_VISIBILITY_PRIVATE = :PRIVATE

      VALID_GROUP_VISIBILITIES = [
        GROUP_VISIBILITY_ALL,
        GROUP_VISIBILITY_SELECTED,
        GROUP_VISIBILITY_PRIVATE
      ].to_set.freeze

      TO_VISIBILITY_MAP = {
        GROUP_VISIBILITY_ALL => "all",
        GROUP_VISIBILITY_SELECTED => "selected",
        GROUP_VISIBILITY_PRIVATE => "private",
      }.freeze

      FROM_VISIBILITY_MAP = {
        "all" => GROUP_VISIBILITY_ALL,
        "selected" => GROUP_VISIBILITY_SELECTED,
        "private" => GROUP_VISIBILITY_PRIVATE,
      }.freeze

      TO_UPDATE_VISIBILITY_MAP = {
        GROUP_VISIBILITY_ALL => :UPDATE_ALL,
        GROUP_VISIBILITY_SELECTED => :UPDATE_SELECTED,
        GROUP_VISIBILITY_PRIVATE => :UPDATE_PRIVATE,
      }.freeze

      TO_UPDATE_ALLOW_PUBLIC_MAP = {
        nil => :ALLOW_PUBLIC_UNKNOWN,
        true => :ALLOW_PUBLIC_ALLOW,
        false => :ALLOW_PUBLIC_DENY,
      }.freeze

      TO_UPDATE_RESTRICTED_TO_WORKFLOWS_MAP = {
        nil => :RESTRICTED_TO_WORKFLOWS_UNKNOWN,
        true => :RESTRICTED_TO_WORKFLOWS_RESTRICTED,
        false => :RESTRICTED_TO_WORKFLOWS_UNRESTRICTED,
      }.freeze

      sig do
        params(
          owner: OrgOrEnterprise,
          include_runners: T.nilable(T::Boolean),
          include_hosted_runner_groups: T.nilable(T::Boolean),
          include_elastic_runners: T.nilable(T::Boolean),
          include_runner_scale_sets: T.nilable(T::Boolean)
        ).returns(TwirpResponse)
      end
      def list_groups(owner:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false)
        request = GitHub::Launch::Services::Runnergroups::ListGroupsRequest.new(
          owner_id: identity(owner),
          plan_owner_id: identity(plan_owner_for(owner)),
          include_runners:,
          is_enterprise_owner: !owner.organization?,
          include_hosted_runner_groups:,
          include_runner_scale_sets:,
          exclude_elastic_runners: !include_elastic_runners
        )

        rescue_rpc { client.list_groups(request) }

      end

      def get_group(owner:, group_id:, include_runners: false, include_hosted_runner_groups: false, include_elastic_runners: false, include_runner_scale_sets: false)
        request = GitHub::Launch::Services::Runnergroups::GetGroupRequest.new(
          owner_id: identity(owner),
          plan_owner_id: identity(plan_owner_for(owner)),
          group_id: group_id,
          include_runners: include_runners,
          is_enterprise_owner: !owner.organization?,
          include_hosted_runner_groups: include_hosted_runner_groups,
          exclude_elastic_runners: !include_elastic_runners,
          include_runner_scale_sets: include_runner_scale_sets,
        )

        rescue_rpc { client.get_group(request) }
      end

      def create_group(actor:, owner:, name:, runner_ids: [], visibility: GROUP_VISIBILITY_SELECTED, allow_public: false, selected_targets: [], selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
        selected_targets = selected_targets_to_global_ids(selected_targets)

        request = GitHub::Launch::Services::Runnergroups::CreateGroupRequest.new(
          owner_id: identity(owner),
          name: name,
          runner_ids: runner_ids,
          visibility: visibility,
          allow_public: allow_public,
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows
        )

        response = rescue_rpc { client.create_group(request) }

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: response.value.runner_group.id,
            runner_group_name: name,
            runner_group_visibility: visibility,
            runner_group_allow_public: allow_public,
            runner_group_restricted_to_workflows: restricted_to_workflows,
            runner_group_selected_workflow_refs: selected_workflow_refs,
            selected_targets: launch_identities_to_github_ids(selected_targets),
            network_configuration_id: network_configuration_id,
            event: "runner_group_created",
          )
        end

        response

      end

      def update_group(actor:, owner:, group_id:, name:, visibility:, allow_public:, selected_targets: nil, selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
        if selected_targets.present?
          selected_targets = selected_targets_to_global_ids(selected_targets)
        end

        request = GitHub::Launch::Services::Runnergroups::UpdateGroupRequest.new(
          owner_id: identity(owner),
          plan_owner_id: identity(plan_owner_for(owner)),
          group_id: group_id,
          name: name,
          update_visibility: TO_UPDATE_VISIBILITY_MAP[visibility],
          allow_public: TO_UPDATE_ALLOW_PUBLIC_MAP[allow_public],
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: TO_UPDATE_RESTRICTED_TO_WORKFLOWS_MAP[restricted_to_workflows]
        )

        response = rescue_rpc { client.update_group(request) }

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            runner_group_name: name,
            runner_group_visibility: visibility,
            runner_group_allow_public: allow_public,
            runner_group_restricted_to_workflows: restricted_to_workflows,
            runner_group_selected_workflow_refs: selected_workflow_refs,
            selected_targets: launch_identities_to_github_ids(selected_targets),
            network_configuration_id: network_configuration_id,
            event: "runner_group_updated",
          )
        end

        response
      end

      sig do
        params(
          actor: User,
          owner: OrgOrEnterprise,
          group_id: Integer
        ).returns(TwirpResponse)
      end
      def delete_group(actor:, owner:, group_id:)
        request = GitHub::Launch::Services::Runnergroups::DeleteGroupRequest.new(
          owner_id: identity(owner),
          group_id:
        )

        response = rescue_rpc { client.delete_group(request) }
        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_removed", actor: actor, runner_group_id: group_id)
        end
        response
      end

      def add_runners(actor:, owner:, group_id:, runner_ids:)
        response = rpc(
          :AddRunners,
          owner_id: identity(owner),
          group_id: group_id,
          runner_ids: runner_ids
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runners_added", runner_group_id: group_id, actor: actor, runner_ids: runner_ids)
        end

        response
      end

      def update_runners(actor:, owner:, group_id:, runner_ids:)
        response = rpc(
          :UpdateRunners,
          owner_id: identity(owner),
          group_id: group_id,
          runner_ids: runner_ids
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runners_updated", runner_group_id: group_id, actor: actor, runner_ids: runner_ids)
        end

        response
      end

      def remove_runner(actor:, owner:, group_id:, runner_id:)
        response = rpc(
          :RemoveRunner,
          owner_id: identity(owner),
          group_id: group_id,
          runner_id: runner_id
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runner_removed", runner_group_id: group_id, actor: actor, runner_id: runner_id)
        end

        response
      end

      def remove_target(actor:, owner:, group_id:, selected_target:)
        request = GitHub::Launch::Services::Runnergroups::RemoveTargetRequest.new(
          owner_id: identity(owner),
          group_id: group_id,
          target_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: selected_target),
        )

        response = rescue_rpc { client.remove_target(request) }

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.target_ids),
            event: "runner_group_updated",
          )
        end

        response
      end

      def update_targets(actor:, owner:, group_id:, selected_targets:)
        request = GitHub::Launch::Services::Runnergroups::UpdateTargetsRequest.new(
          owner_id: identity(owner),
          group_id: group_id,
          target_ids: selected_targets_to_global_ids(selected_targets),
        )

        response = rescue_rpc { client.update_targets(request) }

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.target_ids),
            event: "runner_group_updated",
          )
        end

        response
      end

      def add_target(actor:, owner:, group_id:, selected_target:)
        request = GitHub::Launch::Services::Runnergroups::AddTargetRequest.new(
          owner_id: identity(owner),
          group_id: group_id,
          target_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: selected_target),
        )

        response = rescue_rpc { client.add_target(request) }

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.target_ids),
            event: "runner_group_updated",
          )
        end

        response
      end

      private

      def twirp_class
        GitHub::Launch::Services::Runnergroups::RunnerGroupsClient
      end

      def instrument_event(owner:, event:, actor:, **args)
        payload = args.merge(
          actor: actor,
        )

        case owner
        when Organization
          payload[:org] = owner
          payload[:runner_group_selected_repository_ids] = payload.delete(:selected_targets) if payload.key?(:selected_targets)
          GitHub.instrument "#{owner.event_prefix}.#{event}", payload
        when Business
          payload[:business] = owner
          payload[:runner_group_selected_organization_ids] = payload.delete(:selected_targets) if payload.key?(:selected_targets)
          GitHub.instrument "enterprise.#{event}", payload
        end
      end

      def launch_identities_to_github_ids(launch_identities)
        return unless launch_identities

        launch_identities.map do |launch_identity|
          Platform::Helpers::NodeIdentification.from_global_id(launch_identity.global_id)&.last&.to_i
        end
      end

      def selected_targets_to_global_ids(selected_targets)
        return unless selected_targets

        selected_targets.map do |target|
          GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: target)
        end
      end

      def plan_owner_for(owner)
        return owner unless owner.organization?
        return owner.business if owner.business.present?

        owner
      end
    end
  end
end
