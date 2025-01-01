# typed: strict
# frozen_string_literal: true

module Notifyd
  module Mobile
    class GateRequestRenderer
      Layout = Notifyd::Proto::Layouts::Mobile

      sig do
        params(
          workflow_run: ::Actions::WorkflowRun,
          repository: ::Repository,
          actor_login: ::String,
        ).void
      end
      def initialize(workflow_run:, repository:, actor_login:)
        @workflow_run = workflow_run
        @repository = repository
        @actor_login = actor_login
      end

      sig { returns(Layout::Basic) }
      def render
        Layout::Basic.new(
          title: "Deployment review in #{@repository.name_with_display_owner}",
          body:  "#{@actor_login} requested your review to deploy in \"#{@workflow_run.name} \##{@workflow_run.run_number}\"",
          url: @workflow_run.permalink,
          thread_id: @workflow_run.permalink(include_host: false),
          thread_type: "approval_requested", # This is what the client uses
          subject_id: @workflow_run.check_suite&.global_relay_id,
        )
      end

      private

      sig { returns(::Actions::WorkflowRun) }
      attr_reader :workflow_run
      sig { returns(::Repository) }
      attr_reader :repository
      sig { returns(::String) }
      attr_reader :actor_login
    end
  end
end
