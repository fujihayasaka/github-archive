# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class DependabotJobSecretsProvider

          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          def get_secrets
            # Dependabot does not support re-running the job via Actions CI. So return empty job/cred token to the
            # the Dependabot job if the actor is not the Dependabot App which is the case when dependabot job is re-run via Actions CI.
            # This will fail the re-run Dependabot job which is expected behavior.
            unless @workflow_run.latest_workflow_run_execution.actor == GitHub.dependabot_github_app_bot
              GitHub.logger.info(
                "Re-running Dependabot jobs via Actions CI by unauthorized actors is not supported.",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "gh.repository.id" => @repository.id,
                "gh.workflow_run.id" => @workflow_run.id,
                "gh.workflow_run.actor" => @workflow_run.latest_workflow_run_execution.actor&.display_login,
              )
              return {}
            end
            payload = Dependabot::Twirp.secret_client.get_secret(workflow_run_id: @workflow_run.id)
            return {} if payload["job_token"].blank? || payload["cred_token"].blank?

            {
              "GITHUB_DEPENDABOT_JOB_TOKEN": payload["job_token"],
              "GITHUB_DEPENDABOT_CRED_TOKEN": payload["cred_token"],
            }
          rescue Dependabot::Twirp::Error => error
            GitHub.logger.error(
              "Error fetching secrets for Dependabot job",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
              "gh.repository.id" => @repository.id,
              "gh.workflow_run.id" => @workflow_run.id,
              "error.message" => error.message,
              "error.backtrace" => error.backtrace,
            )
            {}
          end
        end
      end
    end
  end
end
