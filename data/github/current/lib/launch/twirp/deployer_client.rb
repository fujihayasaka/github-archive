# typed: strict
# frozen_string_literal: true

module Launch
  module Twirp
    class DeployerClient < Launch::Twirp::BaseClient

      Entity = T.type_alias { BaseClient::Entity }

      sig do
        params(
          launch_deployer_twirp_address: T.nilable(String),
          launch_deployer_hmac_secret: T.nilable(String),
        ).void
      end
      def initialize(
        launch_deployer_twirp_address: GitHub.launch_deployer_twirp_address,
        launch_deployer_hmac_secret: GitHub.launch_deployer_hmac_secret
      )
        super(
          launch_deployer_twirp_address: launch_deployer_twirp_address,
          launch_deployer_hmac_secret: launch_deployer_hmac_secret,
          request_timeout_secs: 8.0,
        )
      end

      sig { params(check_suite: CheckSuite, actor: T.nilable(User), force: T::Boolean).returns(TwirpResponse) }
      def cancel_workflow(check_suite:, actor:, force:)
        Failbot.push(check_suite_status: check_suite.status)

        cancel_args = {
          check_suite_id: identity(check_suite),
          force: force,
        }.tap do |args|
          if actor.present?
            args[:canceled_by_id] = actor.id
            args[:canceled_by_name] = actor.display_login
            args[:canceled_by_global_id] = identity(actor)
          end
        end

        rpc(:WorkflowCancel, cancel_args)
      end

      sig { params(entities: T::Array[Entity]).returns(TwirpResponse) }
      def get_tenant_ids(entities)
        rpc(:GetTenantIds, owner_ids: entities.map { |entity| identity(entity) })
      end

      sig do
        params(
          repository: Repository,
          integration_name: String,
          actor: User,
          workflow: String,
          ref: String,
          inputs: T.nilable(T::Hash[T.untyped, T.untyped]),
          workflow_name: String,
          slug: String,
          visibility: Symbol,
        ).returns(TwirpResponse)
      end
      def run_dynamic_workflow(repository:, integration_name:, actor:, workflow:, ref:, inputs:, workflow_name:, slug:, visibility:)
        args = {
          repository_id: identity(repository),
          actor_id: identity(actor),
          # Preserve the existing behavior for run_dynamic_workflow
          actor_login: actor.login, # rubocop:disable GitHub/DoNotAllowLogin
          integration_name:,
          workflow:,
          ref:,
          inputs:,
          workflow_name:,
          slug:,
          visibility:,
          owner_id: repository.owner_id,
        }

        rpc(:RunDynamicWorkflow, args)
      end

      sig { params(repository: Repository).returns(TwirpResponse) }
      def setup_repository(repository:)
        # For enterprises and forks, the repository plan owner is not the same as the Actions plan owner
        actions_plan_owner_id = repository.async_actions_plan_owner.sync.id
        owner = T.must(repository.owner)

        rpc(
          :SetupRepository,
          repository_id: identity(repository),
          owner_id: identity(owner),
          plan_owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: actions_plan_owner_id),
          name: repository.name,
          owner: owner.login, # rubocop:disable GitHub/DoNotAllowLogin
        )
      end

      sig { params(target: Entity).returns(TwirpResponse) }
      def setup_tenant(target)
        # Enterprise falls back to 30 seconds from config/unicorn.rb
        # whereas prod has a 10 second limit from GLB
        timeout_ms = GitHub.enterprise? ? 25_000 : 7_000

        rpc(
          :SetupTenant,
          global_relay_id: identity(target),
          owner_global_relay_id: target.is_a?(Repository) ? identity(T.must(target.owner)) : nil,
          timeout_ms:,
        )
      end

      sig { params(repository: Repository).returns(TwirpResponse) }
      def list_schedules(repository)
        request = GitHub::Launch::Pbtypes::Deploy::ListSchedulesRequest.new(
          environment: launch_environment,
          repository_node_id: identity(repository)
        )
        rescue_rpc { client.list_schedules(request) }
      end

      sig { params(repository: Repository, workflow_file_path: String).returns(TwirpResponse) }
      def disable_scheduled_workflow(repository, workflow_file_path)
        request = GitHub::Launch::Pbtypes::Deploy::DisableScheduledWorkflowRequest.new(
          environment: launch_environment,
          repository_node_id: identity(repository),
          workflow_file_path: workflow_file_path
        )
        rescue_rpc { client.disable_scheduled_workflow(request) }
      end

      sig { params(repository: Repository, actor: Entity).returns(TwirpResponse) }
      def synchronize_scheduled_workflows(repository, actor)
        request = GitHub::Launch::Pbtypes::Deploy::SynchronizeScheduledWorkflowsRequest.new(
          ref: repository.default_branch_ref.qualified_name,
          repository_node_id: identity(repository),
          installation_id: repository.actions_app_installation.id,
          actor_node_id: identity(actor)
        )
        rescue_rpc { client.synchronize_scheduled_workflows(request) }
      end

      sig { params(owner_id: Integer, owner_global_id: String, owner_name: String, admin_event: String).returns(TwirpResponse) }
      def report_admin_event_for_billing_owner(owner_id, owner_global_id, owner_name, admin_event)
        request = GitHub::Launch::Services::Deploy::ReportAdminEventForBillingOwnerRequest.new(
          owner_id: owner_id,
          owner_global_id: owner_global_id,
          owner_name: owner_name,
          admin_event: admin_event
        )
        rescue_rpc { client.report_admin_event_for_billing_owner(request) }
      end

      private

      sig { returns(T.class_of(GitHub::Launch::Services::Deploy::LaunchDeploymentServiceClient)) }
      def twirp_class
        GitHub::Launch::Services::Deploy::LaunchDeploymentServiceClient
      end
    end
  end
end
