# frozen_string_literal: true

# Stub for development environments that currently just generates a command
# to run the update job via github/dependabot-action.
#
# TODO: Run the action directly in a subprocess.
# See: https://github.com/github/dependabot-updates/issues/1751
module RunUpdater
  class Development
    attr_reader :job, :job_token, :credentials_token, :instance_type, :priority

    def initialize(job, job_token, credentials_token, instance_type, priority)
      @job = job
      @job_token = job_token
      @credentials_token = credentials_token
      @instance_type = instance_type
      @priority = priority
    end

    def run
      job_args = {
        "--job-id": job.id,
        "--job-token": job_token,
        "--credentials-token": credentials_token,
        "--dependabot-api-url": Dependabot::Application.dependabot_actions_api_endpoint(nil),
        "--dependabot-api-docker-url": Prius.get(:dependabot_api_container_endpoint),
      }.compact

      shell.say <<~MSG

        🚧 Stubbed Update Job Enqueued 🚧

        To perform the job using github/dependabot-action, run:

          npm run dependabot -- #{job_args.map { |k, v| "#{k} #{v}" }.join(' ')}

      MSG
    end

    private

    def shell
      Stafftools::Cli::Util.shell
    end
  end
end
