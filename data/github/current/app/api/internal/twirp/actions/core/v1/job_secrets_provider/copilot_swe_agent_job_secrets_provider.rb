# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CopilotSweAgentJobSecretsProvider
          include GitHub::Memoizer

          class CopilotSweAgentJobSecretsError < StandardError; end
          class GetSecretsError < CopilotSweAgentJobSecretsError; end
          class NotFoundError < CopilotSweAgentJobSecretsError; end

          sig do
            params(
              repository: T.nilable(Repository),
              workflow_run: T.nilable(Actions::WorkflowRun),
              bare_job_name: T.nilable(String),
              environment_name: T.nilable(String),
              is_hosted_runner: T.nilable(T::Boolean),
              dynamic_workflow: T.nilable(MonolithTwirp::Actions::Core::V1::DynamicWorkflow),
            ).void
          end
          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          sig { returns(T::Hash[Symbol, String]) }
          def get_secrets
            raise NotFoundError, "repository is missing" if @repository.nil?
            raise NotFoundError, "workflow_run is missing" if @workflow_run.nil?
            raise NotFoundError, "dynamic_workflow is missing" if @dynamic_workflow.nil?

            # Copilot SWE Agent does not support re-running the job via Actions CI. So return empty job/cred token to the
            # the Copilot SWE Agent job if the this is a re-run job via Actions CI.
            # This will fail the re-run Copilot SWE Agent job which is expected behavior.
            if @workflow_run.has_multiple_attempts
              GitHub.logger.info(
                "Re-running Copilot SWE Agent jobs via Actions CI is not supported.",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "gh.repository.id" => @repository.id,
                "gh.workflow_run.id" => @workflow_run.id,
              )
              return {}
            end

            raise NotFoundError, "dynamic_workflow.inputs is missing" if @dynamic_workflow.inputs.nil?

            user_id = @dynamic_workflow.inputs["COPILOT_AGENT_ACTOR_ID"]
            raise NotFoundError, "COPILOT_AGENT_ACTOR_ID is missing from inputs" if user_id.nil?

            user = User.find_by(id: user_id)
            raise NotFoundError, "user does not exist" if user.nil?

            integration = ::Apps::Privileged.integration(:copilot_swe_agent)
            raise NotFoundError, "integration does not exist" if integration.nil?

            # Get the installation for the owner of the copilot-developer-action repository
            # so that we can generate an archive URL, using the bot's access
            installation = integration.installations.find_by(target_id: action_repo.owner_id)
            raise NotFoundError, "installation for owner_id #{action_repo.owner_id} does not exist" if installation.nil?
            new_access = integration.grant(user)
            token, _ = new_access.redeem

            {
              "GITHUB_COPILOT_API_TOKEN": token,
              "GITHUB_COPILOT_INTEGRATION_ID": "copilot-developer",
              "GITHUB_COPILOT_ACTION_DOWNLOAD_URL": get_action_codeload_url(installation.bot),
            }
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            raise GetSecretsError, "Error in get_secrets: #{e.message}"
          end

          private

          sig { returns(Repository) }
          memoize def action_repo
            Repository.nwo("github/copilot-developer-action")
          end

          sig { params(user: User).returns(String) }
          def get_action_codeload_url(user)
            ac = action_repo.archive_command(action_repo.default_branch, "tar.gz")
            ac.codeload_url(user)
          end
        end
      end
    end
  end
end
