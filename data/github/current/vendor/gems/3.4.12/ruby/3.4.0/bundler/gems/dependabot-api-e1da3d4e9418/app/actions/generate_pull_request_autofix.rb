# frozen_string_literal: true

require "excon"

class GeneratePullRequestAutofix
  TS_FAILURE_LOG_PREFIX = /TS\d{4,6}:/

  FETCH_JOB_LOG_IGNORE_ERRORS = [
    # Forbidden errors should not be retried
    Octokit::Forbidden,
    Excon::Error::Forbidden,

    # The GitHub REST API can return 410/Gone for expired
    # jog logs.
    Octokit::Gone,
    Excon::Error::Gone,
  ].freeze
  FETCH_JOB_LOG_RETRY_ERRORS = [
    # NotFound while fetching logs usually indicates that logs are not available yet.
    # We've already checked that the associated check run is completed so this is
    # most likely a timing problem.
    Octokit::NotFound,
    Excon::Error::NotFound,
  ].freeze

  def initialize(autofix_job:)
    @autofix_job = autofix_job
  end

  def run # rubocop:disable Metrics/AbcSize
    return unless pr.autofix_candidate?

    autofix_job.observe_stage(stage: AutofixSuggestionJob::Stages::START) do
      Dependabot::Logger.info(
        msg: "Autofix candidate",
        "dependabot_commit_ci_status": pr.dependabot_commit_ci_status,
        "head_commit_ci_status": pr.head_commit_ci_status,
        "dependabot_was_last_committer": pr.dependabot_was_last_committer?,
        "pr.dependabot_commit_sha": pr.dependabot_commit_sha,
        "pr.head_commit_sha": pr.head_commit_sha,
      )

      next clear_code_scanning_alert if pr.head_commit_ci_status == GitHub::CheckRun::Conclusion::SUCCESS
      next unless pr.dependabot_was_last_committer?

      # autofixes are currently limited to ts build failures
      next unless failed_actions_runs.any? { |check_run| typescript_failure?(check_run: check_run) }

      create_check_run_for_job_if_missing

      response = installation_github_client.post("repositories/#{pr.repo.github_id}/actions/dynamic", workflow_args)
      pr.actions_workflow_run_id = response[:workflow_run_id]
    end
  end

  private

  attr_reader :autofix_job

  def failed_actions_runs
    # autofixes are limited to actions check runs
    # with failures from build or test steps
    check_runs = installation_github_client.check_runs_for_ref(
      pr.repo.github_id,
      pr.dependabot_commit_sha,
      accept: "application/vnd.github.antiope-preview+json",
    ).check_runs

    allowed_owners = %w(github github-enterprise)
    check_runs.select do |check_run|
      check_run.app.slug == "github-actions" &&
        allowed_owners.include?(check_run.app.owner.login) &&
        check_run.status == GitHub::CheckRun::Status::COMPLETED &&
        check_run.conclusion == GitHub::CheckRun::Conclusion::FAILURE
    end
  rescue Octokit::Forbidden
    []
  end

  # Returns whether a check run had a failure from building typescript code,
  # and not from installing dependencies.
  def typescript_failure?(check_run:)
    logs_url = installation_github_client.workflow_run_job_logs(
      pr.repo.github_id,
      check_run.id
    )

    Excon.get(logs_url, expects: [200]).body.match?(TS_FAILURE_LOG_PREFIX)
  rescue *FETCH_JOB_LOG_IGNORE_ERRORS => e
    Dependabot::Logger.error(
      msg: "Failed to evaluate PR checkrun for typescript failures",
      "exception.message": e.message,
      "exception.type": e.class.name,
      "pr.github_number": pr.github_number,
      "check_run.id": check_run.id
    )
    false
  end

  def installation_github_client
    @installation_github_client ||= GitHubHelpers::ClientWithRetries.new(
      account: pr.repo.account,
      etag_caching: true
    )
  end

  def pr
    autofix_job.pull_request
  end

  def workflow_args
    {
      workflow: workflow_yaml,
      ref: ref,
      workflow_name: "Dependabot Autofix",
      slug: "dependabot-autofix",
    }
  end

  def ref
    pr.repo.default_branch
  end

  def workflow_yaml # rubocop:disable Metrics/MethodLength
    env_hash = {
      GITHUB_TOKEN: %(${{ secrets.GITHUB_TOKEN }}),
      GITHUB_DEPENDABOT_JOB_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_JOB_TOKEN }}),
      GITHUB_DEPENDABOT_CRED_TOKEN: %(${{ secrets.GITHUB_DEPENDABOT_CRED_TOKEN }}),
      DEPENDABOT_API_URL: Dependabot::Application.dependabot_actions_api_endpoint(pr.repo.account),
      GITHUB_API_URL: Dependabot::Application.target_github_api_endpoint(pr.repo.account),
      GH_HOST: Dependabot::Application.target_github_hostname(pr.repo.account),
    }

    node_env_hash = {
      NODE_AUTH_TOKEN: env_hash[:GITHUB_DEPENDABOT_JOB_TOKEN],
      NPM_CONFIG_USERCONFIG: "/home/runner/work/_temp/.npmrc",
    }

    {
      name: "Dependabot Autofix",
      on: "dynamic",
      jobs: {
        Autofix: {
          "runs-on": %w(ubuntu-latest),
          permissions: {
            contents: "read",
            actions: "read",
            "pull-requests": "read",
            "security-events": "write",
          },
          steps: [
            {
              name: "Checkout",
              uses: "actions/checkout@v3", # TODO: Pin to a version
              with: {
                ref: autofix_job.target_sha,
              },
            },
            {
              name: "Set up node",
              uses: "actions/setup-node@v3", # TODO: Pin to a version
              with: {
                "node-version": "22",
                "registry-url": "https://npm.pkg.github.com",
                scope: "@github",
                "always-auth": true,
                # For now, let's require configuring the GHPR_TOKEN secret on
                # the repo's we're running this against. That doesn't scale, but
                # it gets us to a point where we can test this out.
                # Opting to not use GITHUB_TOKEN so we can test in dsp-testing etc
              },
            },
            {
              name: "Install Dependabot Autofix",
              run: "npm install -g @github/dependabot-autofix",
              env: node_env_hash,
            },
            {
              name: "Generate Autofix SARIF",
              run: "dependabot-autofix #{pr.github_url} ./ ./dependabot.sarif",
              env: env_hash,
            },
            {
              name: "Debug SARIF",
              run: "cat ./dependabot.sarif",
            },
            {
              name: "Upload SARIF",
              run: "curl -X POST --data-binary @./dependabot.sarif \
                   -H 'Content-Type: application/json' \
                   -H 'Authorization: ${{ env.GITHUB_DEPENDABOT_CRED_TOKEN }}' \
                   ${{ env.DEPENDABOT_API_URL }}/autofix_suggestion_jobs/#{autofix_job.id}/sarif",
              env: env_hash,
            },
          ],
        },
      },
    }.deep_stringify_keys.to_yaml
  end

  def create_check_run_for_job_if_missing
    return unless autofix_job.check_run_id.nil?

    check_run = installation_github_client.create_check_run(
      pr.repo.github_id,
      "Copilot Autofix",
      autofix_job.target_sha,
      {
        external_id: autofix_job.id.to_s,
        status: GitHub::CheckRun::Status::IN_PROGRESS,
        started_at: Time.now.utc,
      }
    )
    autofix_job.update!(check_run_id: check_run.id)
  end

  def clear_code_scanning_alert
    SubmitSarif.new(sarif_contents: blank_sarif, autofix_job: autofix_job).run
  end

  def blank_sarif
    {
      "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
      version: "2.1.0",
      runs: [{
        tool: {
          driver: {
            name: "Dependabot",
            semanticVersion: "2.17.6",
            rules: [
              {
                id: "js/breaking-change",
              },
            ],
          },
          results: [],
        },
      }],
    }.to_json
  end
end
