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

      private

      def twirp_class
        ::GitHub::ActionsRunService::Api::Twirp::V1::RunServiceClient
      end
    end
  end
end
