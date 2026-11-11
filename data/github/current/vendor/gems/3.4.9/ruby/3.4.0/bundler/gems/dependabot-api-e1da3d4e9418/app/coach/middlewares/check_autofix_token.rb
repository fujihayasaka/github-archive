# frozen_string_literal: true

require "rbnacl"
require "renderer"

module Middlewares
  class CheckAutofixToken < Coach::Middleware
    uses CheckParams, id: { type: [String, Integer] }

    provides :token, :autofix_job

    def call
      return no_autofix_job_error if autofix_job.nil?

      autofix_job.observe_stage(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE) do
        return no_token_error if token.nil?
        return invalid_token_error unless token_valid

        provide(token: token)
        provide(autofix_job: autofix_job)
      end

      # Append job information to the error context
      Dependabot::Exceptions.push(autofix_job.telemetry_attributes)
      next_middleware.call
    end

    private

    def token
      base_64_token = request.headers["Authorization"]
      return if base_64_token.nil?

      # New job/cred token has prefix of dependabot-pr_ with a
      # 32 bit checksum in the last 6 digits of each token.
      # Format of new job token: "dependabot-pr_L4aB8YbwZrxDsTNTzn0RTFDFVkVzxN/AhQJcvumMUu0=0nE82Q".
      base_64_token = base_64_token.delete_prefix(PullRequest::DEPENDABOT_PR_TOKEN_PREFIX)
      # Removing checksum from the base_64_token token
      base_64_token = base_64_token[0..-7]
      @decoded_token ||= Base64.strict_decode64(base_64_token)
    rescue ArgumentError
      # If the token can't be Base64 decoded, leave it as is.
      base_64_token
    end

    def autofix_job_id
      params[:id].to_i
    end

    def token_valid
      return false if token.nil?
      return false if pull_request.nil?

      hashed_token = Base64.strict_encode64(RbNaCl::Hash.sha256(token))
      hashed_token == pull_request.hashed_token
    end

    def autofix_job
      return @autofix_job if defined?(@autofix_job)

      @autofix_job = AutofixSuggestionJob.find_by(id: autofix_job_id)
    end

    def pull_request
      autofix_job&.pull_request
    end

    def no_autofix_job_error
      details = "A record could not be found for autofix suggestion job: #{autofix_job_id}"
      AutofixSuggestionJob::Stages.record_error(
        stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE,
        error: RuntimeError.new(details),
        "gh.dependabot_api.autofix_suggestion_job.id": autofix_job_id
      )

      Renderer.render_error(
        status: 404,
        title: "Not found",
        detail: details,
      )
    end

    def no_token_error
      details = "No token provided in the Authorization header"
      AutofixSuggestionJob::Stages.record_error(
        stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE,
        error: RuntimeError.new(details),
        "gh.dependabot_api.autofix_suggestion_job.id": autofix_job_id
      )
      autofix_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)

      Renderer.render_error(
        status: 401,
        title: "Unauthorized",
        detail: details,
      )
    end

    def invalid_token_error
      details = "Token invalid"
      AutofixSuggestionJob::Stages.record_error(
        stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE,
        error: RuntimeError.new(details),
        "gh.dependabot_api.autofix_suggestion_job.id": autofix_job_id
      )
      autofix_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)

      Renderer.render_error(
        status: 403,
        title: "Forbidden",
        detail: details,
      )
    end
  end
end
