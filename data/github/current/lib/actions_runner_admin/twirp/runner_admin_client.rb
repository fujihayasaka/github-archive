# typed: true
# frozen_string_literal: true

require "actions-runner-admin"

# These calls are defined here:
# https://github.com/github/actions-proto/blob/main/proto/runner-admin/api/v1/runner_resource_service.proto
module ActionsRunnerAdmin
  module Twirp
    class RunnerAdminClient < ActionsRunnerAdmin::Twirp::BaseClient

      GROUP_VISIBILITY_ALL = :VISIBILITY_ALL
      GROUP_VISIBILITY_SELECTED = :VISIBILITY_SELECTED

      TO_DISPLAY_VISIBILITY_MAP = {
        GROUP_VISIBILITY_ALL => "all",
        GROUP_VISIBILITY_SELECTED => "selected",
      }.freeze

      TO_ADMIN_VISIBILITY_MAP = {
        ALL: GROUP_VISIBILITY_ALL,
        SELECTED: GROUP_VISIBILITY_SELECTED,
      }.freeze

      TO_UPDATE_VISIBILITY_MAP = {
        ALL: :UPDATE_VISIBILITY_ALL,
        SELECTED: :UPDATE_VISIBILITY_SELECTED,
      }.freeze

      TO_UPDATE_ALLOW_PUBLIC_MAP = {
        nil => :UPDATE_ALLOW_PUBLIC_UNKNOWN,
        true => :UPDATE_ALLOW_PUBLIC_ALLOW,
        false => :UPDATE_ALLOW_PUBLIC_DENY,
      }.freeze

      TO_UPDATE_RESTRICTED_TO_WORKFLOWS_MAP = {
        nil => :UPDATE_RESTRICTED_TO_WORKFLOWS_UNKNOWN,
        true => :UPDATE_RESTRICTED_TO_WORKFLOWS_RESTRICTED,
        false => :UPDATE_RESTRICTED_TO_WORKFLOWS_UNRESTRICTED,
      }.freeze

      def get_runner_group(owner:, group_id:, include_runners:)
        rpc(
          :GetRunnerGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          include_runners: include_runners,
        )
      end

      def list_runner_groups(owner:, include_runners: false)
        rpc(
          :ListRunnerGroups,
          entity: build_runner_admin_entity(owner),
          include_runners: include_runners,
        )
      end

      def add_runner_group(actor:, owner:, name:, runner_ids:, visibility:, selected_targets:, allow_public:, selected_workflow_refs:, restricted_to_workflows:, network_configuration_id: nil)
        selected_global_ids = selected_targets_to_global_ids(selected_targets)

        response = rpc(
          :AddRunnerGroup,
          entity: build_runner_admin_entity(owner),
          name: name,
          runner_ids: runner_ids,
          visibility: TO_ADMIN_VISIBILITY_MAP[visibility],
          selected_targets: selected_global_ids,
          allow_public: allow_public,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
          #selected_orgs: ,
          #is_default: ,
        )

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

      def update_runner_group(actor:, owner:, group_id:, name:, runner_ids:, selected_targets:, update_visibility:, allow_public:, selected_workflow_refs:, restricted_to_workflows:, network_configuration_id: nil)
        if selected_targets.present?
          selected_global_ids = selected_targets_to_global_ids(selected_targets)
        end

        response = rpc(
          :UpdateRunnerGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          name: name,
          runner_ids: runner_ids,
          selected_targets: selected_global_ids,
          update_visibility: TO_UPDATE_VISIBILITY_MAP[update_visibility],
          allow_public: TO_UPDATE_ALLOW_PUBLIC_MAP[allow_public],
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: TO_UPDATE_RESTRICTED_TO_WORKFLOWS_MAP[restricted_to_workflows],
          #selected_entities: ,
          #is_default: ,
        )

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            runner_group_name: name,
            runner_group_visibility: update_visibility,
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

      def delete_runner_group(actor:, owner:, group_id:)
        response = rpc(
          :DeleteRunnerGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_removed", actor: actor, runner_group_id: group_id)
        end

        response
      end

      def get_runner(owner:, runner_id:)
        rpc(
          :GetRunner,
          entity: build_runner_admin_entity(owner),
          id: runner_id,
        )
      end

      def list_runners(owner:, name:, per_page:, page:)
        rpc(
          :ListRunners,
          entity: build_runner_admin_entity(owner),
          name: name,
          page: page,
          per_page: per_page
        )
      end

      def list_runners_for_group(owner:, group_id:, page:, per_page:)
        rpc(
          :ListRunnersForGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          page: page,
          per_page: per_page
        )
      end

      def add_runner(owner:, group_id:, name:, version:, updates_disabled:, ephemeral:, labels:, public_key:)
        rpc(
          :AddRunner,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          name: name,
          version: version,
          updates_disabled: updates_disabled,
          labels: labels,
          ephemeral: ephemeral,
          public_key: public_key,
        )
      end

      def update_runner(owner:, runner_id:, group_id:, name:, version:, updates_disabled:, ephemeral:, labels:, public_key:, replace_labels:)
        rpc(
          :UpdateRunner,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          name: name,
          id: runner_id,
          version: version,
          updates_disabled: updates_disabled,
          labels: labels,
          ephemeral: ephemeral,
          public_key: public_key,
          replace_labels: replace_labels,
        )
      end

      def delete_runner(owner:, runner_id:)
        rpc(
          :DeleteRunner,
          entity: build_runner_admin_entity(owner),
          runner_id: runner_id,
        )
      end

      private

      def twirp_class
        ::GitHub::ActionsRunnerAdmin::Api::V1::RunnerResourceServiceClient
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
          GitHub::ActionsRunnerAdmin::Entities::V1::Identity.new(global_id: target)
        end
      end
    end
  end
end
