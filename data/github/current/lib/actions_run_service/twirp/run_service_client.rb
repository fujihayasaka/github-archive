# typed: true
# frozen_string_literal: true

require "actions-run-service"

module ActionsRunService
  module Twirp
    class RunServiceClient < ActionsRunService::Twirp::BaseClient
      def cancel_plan(plan_id:, cancelled_by: "", is_force_cancel:)
        rpc(
          :CancelPlan,
          plan_id: plan_id,
          cancelled_by: cancelled_by,
          reason: "cancelled by user",
          is_force_cancel: is_force_cancel,
        )
      end

      def notify_gate(request)
        rpc(
          :NotifyGate,
          request
        )
      end

      def debug_job(request)
        rpc(
          :DebugJob,
          request
        )
      end

      def list_concurrency_groups(repository_global_id:, cursor: nil, limit: 50)
        rpc(
          :ListConcurrencyGroups,
          repository_global_id: repository_global_id,
          cursor: cursor,
          limit: limit
        )
      end

      def get_concurrency_group(repository_global_id:, group_name:)
        rpc(
          :GetConcurrencyGroup,
          repository_global_id: repository_global_id,
          group_name: group_name
        )
      end

      private

      def twirp_class
        ::GitHub::ActionsRunService::Api::Twirp::V1::RunServiceClient
      end
    end
  end
end
