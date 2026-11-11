# frozen_string_literal: true

class SubmitSarif
  def initialize(sarif_contents:, autofix_job:)
    @sarif_contents = sarif_contents
    @autofix_job = autofix_job
  end

  attr_reader :sarif_contents, :autofix_job

  def run
    autofix_job.observe_stage(stage: AutofixSuggestionJob::Stages::SUBMIT_AUTOFIX_REQUEST) do
      autofix_job.update!(sarif_content: JSON.parse(sarif_contents))
      repo = autofix_job.pull_request.repo

      if for_autofix_demo?(repo)
        Dependabot::Logger.info(
          msg: "Submitting SARIF",
          destination: "Code Scanning",
        )
        github_client.post("repos/#{repo.account.github_login}/#{repo.name}/code-scanning/sarifs", sarif_upload_args)
      else
        Dependabot::Logger.info(
          msg: "Submitting SARIF",
          destination: "Turboscan",
        )
        Turboscan::Autofix.new.generate_dependabot_fix(autofix_job)
      end
    end
  rescue StandardError
    autofix_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)
    raise
  end

  private

  def for_autofix_demo?(repo)
    repo.config_feature_enabled?(:autofix_demo)
  end

  def sarif_upload_args
    {
      sarif: sarif_data,
      commit_sha: autofix_job.target_sha,
      ref: "refs/pull/#{autofix_job.pull_request.github_number}/head",
    }
  end

  def sarif_data
    Tempfile.create("sarif.gz") do |tempfile|
      Zlib::GzipWriter.open(tempfile) do |gz_file|
        gz_file.write sarif_contents
      end
      [tempfile.read].pack("m0") # Base64.strict_encode64
    end
  end

  def github_client
    @github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(
        access_token: Prius.get(:dependabot_security_events_token),
        api_endpoint: Dependabot::Application.target_github_api_endpoint(autofix_job.pull_request.repo.account),
      )
  end
end
