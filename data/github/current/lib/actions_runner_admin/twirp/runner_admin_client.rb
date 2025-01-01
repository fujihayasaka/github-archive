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
      GROUP_VISIBILITY_PRIVATE = :VISIBILITY_PRIVATE


      TO_VISIBILITY_MAP = {
        GROUP_VISIBILITY_ALL => "all",
        GROUP_VISIBILITY_SELECTED => "selected",
        GROUP_VISIBILITY_PRIVATE => "private",
      }.freeze


      def get_runner_group(entity_id:, repo_id:, org_id:, enterprise_id:, group_id:)
        rpc(
          :GetRunnerGroup,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          group_id: group_id,
        )
      end

      def list_runner_groups(entity_id:, repo_id:, org_id:, enterprise_id:)
        rpc(
          :ListRunnerGroups,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
        )
      end

      def get_runner(entity_id:, repo_id:, org_id:, enterprise_id:, runner_id:)
        rpc(
          :GetRunner,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          id: runner_id,
        )
      end

      def list_runners(entity_id:, repo_id:, org_id:, enterprise_id:, name:, per_page:, page:)
        rpc(
          :ListRunners,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          name: name,
          page: page,
          per_page: per_page
        )
      end

      def list_runners_for_group(entity_id:, repo_id:, org_id:, enterprise_id:, group_id:, page:, per_page:)
        rpc(
          :ListRunnersForGroup,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          group_id: group_id,
          page: page,
          per_page: per_page
        )
      end

      def add_runner(entity_id:, repo_id:, org_id:, enterprise_id:, group_id:, name:, version:, updates_disabled:, ephemeral:, labels:, public_key:)
        rpc(
          :AddRunner,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          group_id: group_id,
          name: name,
          version: version,
          updates_disabled: updates_disabled,
          labels: labels,
          ephemeral: ephemeral,
          public_key: public_key,
        )
      end

      def update_runner(entity_id:, repo_id:, org_id:, enterprise_id:, runner_id:, group_id:, name:, version:, updates_disabled:, ephemeral:, labels:, public_key:, replace_labels:)
        rpc(
          :UpdateRunner,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
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

      def delete_runner(entity_id:, repo_id:, org_id:, enterprise_id:, runner_id:)
        rpc(
          :DeleteRunner,
          entity: build_entity(entity_id, repo_id, org_id, enterprise_id),
          runner_id: runner_id,
        )
      end

      private

      def twirp_class
        ::GitHub::ActionsRunnerAdmin::Api::V1::RunnerResourceServiceClient
      end
    end
  end
end
