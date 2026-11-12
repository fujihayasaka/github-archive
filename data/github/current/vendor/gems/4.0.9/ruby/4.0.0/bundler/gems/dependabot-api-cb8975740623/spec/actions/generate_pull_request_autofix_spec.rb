# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeneratePullRequestAutofix do
  subject(:action) do
    described_class.new(autofix_job: autofix_job)
  end

  let(:account) { FactoryBot.create(:account, :active) }
  let(:repo) { FactoryBot.create(:repo, account: account) }
  let(:updated_dependencies) do
    [
      FactoryBot.create(
        :updated_dependency,
        package_manager: PackageManagers::NPM_AND_YARN,
        requirements: "1.2.3", previous_requirements: "1.2.0"
      ),
    ]
  end
  let(:base_commit_ci_status) { GitHub::CheckRun::Conclusion::SUCCESS }
  let(:dependabot_commit_ci_status) { GitHub::CheckRun::Conclusion::FAILURE }
  let(:head_commit_ci_status) { GitHub::CheckRun::Conclusion::FAILURE }
  let(:dependabot_commit_sha) { "dependabotcommitsha" }
  let(:head_commit_sha) { "dependabotcommitsha" }
  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      repo: repo,
      updated_dependencies: updated_dependencies,
      base_commit_ci_status: base_commit_ci_status,
      dependabot_commit_ci_status: dependabot_commit_ci_status,
      head_commit_ci_status: head_commit_ci_status,
      head_commit_sha: head_commit_sha,
      affected_directories: ["./"],
      dependabot_commit_sha: "dependabotcommitsha"
    )
  end
  let!(:autofix_job) do
    create(:autofix_suggestion_job,
           pull_request: pull_request,
           target_sha: pull_request.head_commit_sha,
           check_run_id: nil)
  end
  let(:execution_id) { "75b5f5dd-870f-4a44-8068-70380837fe80" }
  let(:workflow_run_id) { 9876543210 }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { "#{github_url}repositories/#{repo.github_id}" }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_checks_data) { fixture("github_responses/check_runs_failed_actions.json") }
  let(:github_actions_job_log) { fixture("github_responses/actions_logs/ts_build_failure.log") }
  let(:check_run_created_data) { fixture("github_responses/check_run_created.json") }

  describe "#run" do
    before do
      allow(pull_request).to receive(:autofix_candidate?).and_return(true)

      github_token = "top secret"
      allow(GitHubHelpers).
        to receive(:access_token_for).
        and_return(github_token)

      # check run call
      stub_request(:get, repo_url + "/commits/dependabotcommitsha/check-runs").
        to_return(status: 200, body: github_checks_data, headers: json_header)

      # actions job log url call
      stub_request(:head, repo_url + "/actions/jobs/24475437427/logs").
        to_return(status: 302, headers: { "Location": "https://example.com/logs" })

      # actions job log call
      stub_request(:get, "https://example.com/logs").
        to_return(status: 200, body: github_actions_job_log)

      # dynamic actions workflow run
      stub_request(:post, repo_url + "/actions/dynamic").
        to_return(
          status: 200,
          body: { execution_id: execution_id, workflow_run_id: workflow_run_id }.to_json,
          headers: json_header
        )

      stub_request(:post, repo_url + "/check-runs").
        to_return(status: 200, body: check_run_created_data, headers: json_header)
    end

    shared_examples "does NOT dispatch the autofix workflow" do
      it "does NOT dispatch the autofix workflow" do
        action.run
        expect(WebMock).not_to have_requested(:post, repo_url + "/actions/dynamic").once
      end
    end

    it "dispatches a Dependabot autofix workflow", :cloud do
      action.run

      expect(WebMock).
        to(have_requested(:post, repo_url + "/actions/dynamic").once.with do |req|
          args = JSON.parse(req.body)
          workflow = YAML.safe_load(args["workflow"])
          jobs = workflow["jobs"]
          job = jobs.values.first

          expect(args["headers"]).not_to be_present

          expect(args["workflow_name"]).to eq("Dependabot Autofix")

          expect(jobs.length).to eq(1)
          expect(jobs.keys.first).to eq("Autofix")
          expect(job["runs-on"]).to eq(%w(ubuntu-latest))
        end)
    end

    context "when the pull request is not an autofix candidate" do
      before do
        allow(pull_request).to receive(:autofix_candidate?).and_return(false)
      end

      include_examples "does NOT dispatch the autofix workflow"
    end

    context "when the head_commit_sha doesn't match the dependabot_commit_sha" do
      let(:head_commit_sha) { "headcommitsha" }

      include_examples "does NOT dispatch the autofix workflow"

      context "and the head_commit_ci_status is success" do
        let(:head_commit_ci_status) { GitHub::CheckRun::Conclusion::SUCCESS }
        let(:expected_url) do
          "#{Dependabot::Application.target_github_api_endpoint(account)}repos/hmarr/business/code-scanning/sarifs"
        end

        before do
          repo.enable_feature(:autofix_demo) # rubocop:disable Dependabot/NoLocalFeatureFlags

          stub_request(:post, expected_url).
            to_return(status: 204)
        end

        include_examples "does NOT dispatch the autofix workflow"

        it "POSTs a sarif to the GitHub API" do
          action.run
          expect(WebMock).to have_requested(:post, expected_url).once
        end
      end
    end

    context "when the PR's checkrun is not a failure" do
      let(:github_checks_data) { fixture("github_responses/check_runs_success_actions.json") }

      include_examples "does NOT dispatch the autofix workflow"
    end

    context "when the PR's failing checkrun is not a GitHub Action" do
      let(:github_checks_data) { fixture("github_responses/check_runs_failed.json") }

      include_examples "does NOT dispatch the autofix workflow"
    end

    context "when the PR's failing GitHub Action is not a TS failure" do
      let(:github_actions_job_log) { fixture("github_responses/actions_logs/npm_test_failure.log") }

      include_examples "does NOT dispatch the autofix workflow"
    end

    context "downloading an actions job log results in 404" do
      context "from the GitHub REST API" do
        before do
          # GitHub actions REST API call
          stub_request(:head, repo_url + "/actions/jobs/24475437427/logs").to_return(status: 404)
        end

        it "raises an error" do
          expect { action.run }.to raise_error(Octokit::NotFound)
        end
      end

      context "when downloading from the file server" do
        before do
          # actions job log download call
          stub_request(:get, "https://example.com/logs").to_return(status: 404)
        end

        it "raises an error" do
          expect { action.run }.to raise_error(Excon::Error::NotFound)
        end
      end
    end

    context "downloading an actions job log results in 410" do
      context "from the GitHub REST API" do
        before do
          # GitHub Actions rest API
          stub_request(:head, repo_url + "/actions/jobs/24475437427/logs").to_return(status: 410)
        end

        include_examples "does NOT dispatch the autofix workflow"
      end

      context "when downloading from the file server" do
        before do
          # actions job log call
          stub_request(:get, "https://example.com/logs").to_return(status: 410)
        end

        include_examples "does NOT dispatch the autofix workflow"
      end
    end

    it "creates a check run for the autofix job", :cloud do
      repo.enable_feature(:autofix_demo) # rubocop:disable Dependabot/NoLocalFeatureFlags
      action.run

      expect(WebMock).
        to(have_requested(:post, repo_url + "/check-runs").once.with do |req|
          args = JSON.parse(req.body)
          expect(args["name"]).to eq("Copilot Autofix")
          expect(args["external_id"]).to eq(autofix_job.id.to_s)
          expect(args["status"]).to eq(GitHub::CheckRun::Status::IN_PROGRESS)
        end)

      # expect the id from the github_responses/check_run_created.json fixture
      expect(autofix_job.check_run_id).to equal(4)
    end

    it "observes an autofix stage" do
      expect(autofix_job).to receive(:observe_stage).with(stage: AutofixSuggestionJob::Stages::START)
      action.run
    end
  end
end
