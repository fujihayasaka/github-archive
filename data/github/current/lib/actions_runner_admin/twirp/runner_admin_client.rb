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

      GROUP_VISIBILITY_ALL_LAUNCH = :ALL
      GROUP_VISIBILITY_SELECTED_LAUNCH = :SELECTED

      TO_DISPLAY_VISIBILITY_MAP = {
        GROUP_VISIBILITY_ALL => "all",
        GROUP_VISIBILITY_SELECTED => "selected",
      }.freeze

      TO_ADMIN_VISIBILITY_MAP = {
        nil => :VISIBILITY_UNKNOWN,
        GROUP_VISIBILITY_ALL_LAUNCH => GROUP_VISIBILITY_ALL,
        GROUP_VISIBILITY_SELECTED_LAUNCH => GROUP_VISIBILITY_SELECTED,
      }.freeze

      TO_UPDATE_VISIBILITY_MAP = {
        nil => :UPDATE_VISIBILITY_UNKNOWN,
        GROUP_VISIBILITY_ALL_LAUNCH => :UPDATE_VISIBILITY_ALL,
        GROUP_VISIBILITY_SELECTED_LAUNCH => :UPDATE_VISIBILITY_SELECTED,
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

      def get_runner_group(owner:, group_id:, include_runners: false)
        rpc(
          :GetRunnerGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          include_runners: include_runners,
        )
      end

      def list_runner_groups(owner:, include_runners: false, include_runner_scale_sets: false)
        rpc(
          :ListRunnerGroups,
          entity: build_runner_admin_entity(owner),
          include_runners: include_runners,
          include_runner_scale_sets: include_runner_scale_sets,
        )
      end

      def add_runner_group(actor:, owner:, name:, runner_ids: [], visibility: GROUP_VISIBILITY_SELECTED_LAUNCH, allow_public: false, selected_targets: [], selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
        selected_targets = selected_targets_to_global_ids(selected_targets)

        response = rpc(
          :AddRunnerGroup,
          entity: build_runner_admin_entity(owner),
          name: name,
          runner_ids: runner_ids,
          visibility: TO_ADMIN_VISIBILITY_MAP[visibility],
          allow_public: allow_public,
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: restricted_to_workflows,
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

      def update_runner_group(actor:, owner:, group_id:, name:, runner_ids: nil, visibility: nil, allow_public:, selected_targets: nil, selected_workflow_refs: [], restricted_to_workflows: selected_workflow_refs.any?, network_configuration_id: nil)
        if selected_targets.present?
          selected_targets = selected_targets_to_global_ids(selected_targets)
        end

        response = rpc(
          :UpdateRunnerGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          name: name,
          runner_ids: runner_ids,
          update_visibility: TO_UPDATE_VISIBILITY_MAP[visibility],
          allow_public: TO_UPDATE_ALLOW_PUBLIC_MAP[allow_public],
          selected_targets: selected_targets,
          selected_workflow_refs: selected_workflow_refs,
          restricted_to_workflows: TO_UPDATE_RESTRICTED_TO_WORKFLOWS_MAP[restricted_to_workflows],
        )

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

      def list_runners(owner:, name: "", page: 0, per_page: 0)
        # Set default pagination if name is provided
        if !name.blank?
          page = 0
          per_page = 0
        end

        rpc(
          :ListRunners,
          entity: build_runner_admin_entity(owner),
          name: name,
          page: page,
          per_page: per_page
        )
      end

      def list_runners_for_group(owner:, group_id:, page: 0, per_page: 0)
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

      def delete_runner(owner:, runner_id:, actor:)
        response = rpc(
          :DeleteRunner,
          entity: build_runner_admin_entity(owner),
          runner_id: runner_id,
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "remove_self_hosted_runner")
        end

        response
      end

      def add_runners_to_group(actor:, owner:, group_id:, runner_ids:)
        response = rpc(
          :SetRunnersForGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          runner_ids: runner_ids,
          replace_runners: false,
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runners_added", runner_group_id: group_id, actor: actor, runner_ids: runner_ids)
        end

        response
      end

      def update_runners_in_group(actor:, owner:, group_id:, runner_ids:)
        response = rpc(
          :SetRunnersForGroup,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          runner_ids: runner_ids,
          replace_runners: true,
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runners_updated", runner_group_id: group_id, actor: actor, runner_ids: runner_ids)
        end

        response
      end

      def remove_runner_from_group(actor:, owner:, group_id:, runner_id:)
        response = rpc(
          :SetRunnersForGroup,
          entity: build_runner_admin_entity(owner),
          group_id: 1,
          runner_ids: [runner_id],
          replace_runners: false,
        )

        if response.call_succeeded?
          instrument_event(owner: owner, event: "runner_group_runner_removed", runner_group_id: group_id, actor: actor, runner_id: runner_id)
        end

        response
      end

      # Runner group permissions

      def add_runner_group_permission(actor:, owner:, group_id:, selected_target:)
        response = rpc(
          :AddRunnerGroupPermissions,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          allowed_entities_to_add: selected_targets_to_global_ids([selected_target]),
        )

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.allowed_entities),
            event: "runner_group_updated",
          )
        end

        response
      end

      def delete_runner_group_permission(actor:, owner:, group_id:, selected_target:)
        response = rpc(
          :DeleteRunnerGroupPermissions,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          allowed_entities_to_delete: selected_targets_to_global_ids([selected_target]),
        )

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.allowed_entities),
            event: "runner_group_updated",
          )
        end

        response
      end

      def set_runner_group_permissions(actor:, owner:, group_id:, selected_targets:)
        response = rpc(
          :SetRunnerGroupPermissions,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          allowed_entities: selected_targets_to_global_ids(selected_targets),
        )

        if response.call_succeeded?
          instrument_event(
            owner: owner,
            actor: actor,
            runner_group_id: group_id,
            selected_targets: launch_identities_to_github_ids(response.value.allowed_entities),
            event: "runner_group_updated",
          )
        end

        response
      end

      # Labels

      def list_labels(owner:)
        rpc(
          :ListLabels,
          entity: build_runner_admin_entity(owner),
        )
      end

      def set_labels(owner:, runner_id:, labels:)
        rpc(
          :SetLabels,
          entity: build_runner_admin_entity(owner),
          runner_id: runner_id,
          labels: labels,
        )
      end

      def update_labels(owner:, runner_id:, labels_to_add:, labels_to_remove:)
        rpc(
          :UpdateLabels,
          entity: build_runner_admin_entity(owner),
          runner_id: runner_id,
          labels_to_add: labels_to_add,
          labels_to_remove: labels_to_remove,
        )
      end

      def add_runner_scale_set(owner:, name:, group_id: 1, labels: [], runner_setting_hash: nil)

        request_labels = labels&.map do |label_hash|
          GitHub::ActionsRunnerAdmin::Api::V1::RunnerScaleSetLabel.new(name: label_hash[:name], type: label_hash[:type])
        end

        rpc(
          :AddRunnerScaleSet,
          entity: build_runner_admin_entity(owner),
          name: name,
          group_id: group_id,
          labels: request_labels,
          runner_setting: runner_setting(runner_setting_hash),
        )
      end

      def list_runner_scale_sets(owner:, group_id: nil, name: nil, page: nil, per_page: nil)
        rpc(
          :ListRunnerScaleSets,
          entity: build_runner_admin_entity(owner),
          group_id: group_id,
          name: name,
          page: page,
          per_page: per_page
        )
      end

      def get_runner_scale_set(owner:, scale_set_id:)
        rpc(
          :GetRunnerScaleSet,
          entity: build_runner_admin_entity(owner),
          id: scale_set_id,
        )
      end

      def update_runner_scale_set(owner:, scale_set_id:, name:, group_id: nil, labels:, runner_setting_hash:)
        rpc(
          :UpdateRunnerScaleSet,
          entity: build_runner_admin_entity(owner),
          id: scale_set_id,
          name: name,
          group_id: group_id,
          labels: labels,
          runner_setting: runner_setting(runner_setting_hash),
        )
      end

      def delete_runner_scale_set(owner:, scale_set_id:)
        rpc(
          :DeleteRunnerScaleSet,
          entity: build_runner_admin_entity(owner),
          id: scale_set_id,
        )
      end

      def create_runner_scale_set_session(owner:, scale_set_id:, session_owner_name:)
        rpc(
          :CreateRunnerScaleSetSession,
          entity: build_runner_admin_entity(owner),
          scale_set_id: scale_set_id,
          owner_name: session_owner_name,
        )
      end

      def refresh_runner_scale_set_session(owner:, scale_set_id:, session_id:)
        rpc(
          :RefreshRunnerScaleSetSession,
          entity: build_runner_admin_entity(owner),
          scale_set_id: scale_set_id,
          session_id: session_id,
        )
      end

      def delete_runner_scale_set_session(owner:, scale_set_id:)
        rpc(
          :DeleteRunnerScaleSetSession,
          entity: build_runner_admin_entity(owner),
          scale_set_id: scale_set_id,
        )
      end

      def generate_jit_runner_config(owner:, name:, runner_group_id:, labels:, work_folder:, github_url:, actor:)
        response = rpc(
          :GenerateJitRunnerConfig,
          entity: build_runner_admin_entity(owner),
          name: name,
          runner_group_id: runner_group_id,
          labels: labels,
          work_folder: work_folder,
          git_hub_url: github_url,
        )

        if response.call_succeeded?
          instrument_event(owner:, actor:, event: "configure_self_hosted_jit_runner")
        end

        response
      end

      def generate_jit_runner_config_for_scale_set(owner:, scale_set_id:, name:, work_folder:)
        rpc(
          :GenerateJitRunnerConfig,
          entity: build_runner_admin_entity(owner),
          scale_set_id: scale_set_id,
          name: name,
          work_folder: work_folder,
        )
      end

      def list_runner_downloads(owner:)
        rpc(
          :ListRunnerDownloads,
          entity: build_runner_admin_entity(owner),
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

      sig { params(selected_targets: T.nilable(T::Array[String])).returns(T.nilable(T::Array[GitHub::ActionsRunnerAdmin::Entities::V1::Identity])) }
      def selected_targets_to_global_ids(selected_targets)
        return unless selected_targets

        selected_targets.map do |target|
          GitHub::ActionsRunnerAdmin::Entities::V1::Identity.new(global_id: target)
        end
      end

      sig { params(runner_setting_hash: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(GitHub::ActionsRunnerAdmin::Api::V1::RunnerSetting)) }
      def runner_setting(runner_setting_hash)
        return nil unless runner_setting_hash
        GitHub::ActionsRunnerAdmin::Api::V1::RunnerSetting.new(
          disable_update: runner_setting_hash[:disableUpdate],
          ephemeral: runner_setting_hash[:ephemeral])
      end
    end
  end
end
