# frozen_string_literal: true

require "rails_helper"
require "dependabot/dependency_file"

# rubocop:disable RSpec/AnyInstance
RSpec.describe PrioritizedJobs::StartUpdateJob::Default do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(update_job) }

  let(:update_config) { repo.update_configs.last }
  let(:installation_id) { 1001 }
  let(:account) do
    FactoryBot.create(
      :account, :active,
      installation_id: installation_id,
      github_login: "old_name",
      github_id: 27347476,
    )
  end
  let(:repo_github_id) { 88632334 }
  let(:repo) do
    FactoryBot.create(
      :repo, :active,
      account: account,
      github_id: repo_github_id,
      name: "old_repo_name",
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_repo) { fixture("github_responses/repo.json") }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:install_access_token_url) do
    "#{github_url}app/global/access_tokens"
  end
  let(:install_access_token) do
    erb_fixture("github_responses/installation_access_token.json")
  end
  let(:redis) { Dependabot.redis }
  let(:repository_settings) do
    {
      actions_fully_enabled: true,
      automated_security_updates_enabled: true,
    }
  end
  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(**repository_settings)
    )
  end

  let(:update_job_runner_type) { nil } # Specify in examples below.
  let(:update_job_trigger_type) { nil } # Specify in examples below.
  let(:update_job) do
    UpdateJob.create!(
      update_config_id: update_config.id,
      runner_type: update_job_runner_type,
      trigger_type: update_job_trigger_type
    )
  end

  let(:runner_class) { nil } # Specify in examples below.

  before do
    # Clear out cached access tokens
    redis.flushdb

    stub_request(:post, install_access_token_url).
      with(body: anything).
      to_return(
        status: 200,
        body: install_access_token,
        headers: json_header,
      )

    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)

    # Spy on the runner class so we can check its config arguments
    allow(runner_class).
      to receive(:new).and_call_original

    FactoryBot.create(:updater_version, env: "prod", ecosystem: "bundler", version: "123")
  end

  shared_examples "a fully implemented job runner" do
    before do
      stub_request(:get, repo_url).
        to_return(status: 200, body: github_repo, headers: json_header)
    end

    let(:update_job_trigger_type) { "push" }

    it "updates the account with the latest GitHub details" do
      expect { job.perform_now }.
        to change { account.reload.github_login }.
        to("dependabot")
    end

    it "updates the repo with the latest GitHub details" do
      expect { job.perform_now }.
        to change { repo.reload.name }.
        to("bump-test")
    end

    it "updates the update job" do
      expect { job.perform_now }.to change(update_job, :hashed_token).from(nil)
    end

    it "kicks off a bumping job" do
      expect(runner_class).to receive(:new).with(update_job, nil)
      expect_any_instance_of(runner_class).to receive(:run)
      perform_enqueued_jobs do
        job.perform_now
      end
    end

    context "with runner settings" do
      let(:repository_settings) do
        {
          actions_fully_enabled: true,
          automated_security_updates_enabled: true,
          dependabot_runner_settings: OpenStruct.new(
            runner_labels: %w(self-hosted custom),
            runner_group: "my-runner-group"
          ),
        }
      end

      it "kicks off a bumping job with runner settings" do
        expected_runner_settings = {
          runner_labels: %w(self-hosted custom),
          runner_group: "my-runner-group",
        }
        expect(runner_class).to receive(:new).with(update_job, expected_runner_settings)
        expect_any_instance_of(runner_class).to receive(:run)
        perform_enqueued_jobs do
          job.perform_now
        end
      end
    end

    context "when Actions is not fully enabled on the repo" do
      let(:repository_settings) do
        {
          actions_fully_enabled: false,
          automated_security_updates_enabled: true,
        }
      end

      it "kicks off a bumping job" do
        expect(runner_class).to receive(:new).with(update_job, nil)
        expect_any_instance_of(runner_class).to receive(:run)
        perform_enqueued_jobs do
          job.perform_now
        end
      end
    end

    context "PrioritizedJobs::StartUpdateJob::Low" do
      subject(:job) { PrioritizedJobs::StartUpdateJob::Low.new(update_job) }

      let(:update_job_trigger_type) { "scan" }

      it "kicks off a bumping job" do
        expect(runner_class).to receive(:new).with(update_job, nil)
        expect_any_instance_of(runner_class).to receive(:run)
        perform_enqueued_jobs do
          job.perform_now
        end
      end

      context "when Actions is not fully enabled on the repo" do
        let(:repository_settings) do
          {
            actions_fully_enabled: false,
            automated_security_updates_enabled: true,
          }
        end

        it "kicks off a bumping job" do
          expect(runner_class).to receive(:new).with(update_job, nil)
          expect_any_instance_of(runner_class).to receive(:run)
          perform_enqueued_jobs do
            job.perform_now
          end
        end
      end
    end

    context "PrioritizedJobs::StartUpdateJob::High" do
      subject(:job) { PrioritizedJobs::StartUpdateJob::High.new(update_job) }

      let(:update_job_trigger_type) { "manual" }

      it "kicks off a bumping job" do
        expect(runner_class).to receive(:new).with(update_job, nil)
        expect_any_instance_of(runner_class).to receive(:run)
        perform_enqueued_jobs do
          job.perform_now
        end
      end

      context "when Actions is not fully enabled on the repo" do
        let(:repository_settings) do
          {
            actions_fully_enabled: false,
            automated_security_updates_enabled: true,
          }
        end

        it "kicks off a bumping job" do
          expect(runner_class).to receive(:new).with(update_job, nil)
          expect_any_instance_of(runner_class).to receive(:run)
          perform_enqueued_jobs do
            job.perform_now
          end
        end
      end
    end

    context "with an invalid job state" do
      it "does not modify enqueued job" do
        update_job.transition_to!(:enqueued)

        expect_any_instance_of(runner_class).not_to receive(:run)
        expect { job.perform_now }.not_to \
          change(update_job, :hashed_token).from(nil)
        expect(update_job.reload.current_state).to eq("enqueued")
      end

      it "raises error on cancelled job" do
        update_job.transition_to!(:cancelled)

        expect { job.perform_now }.to \
          raise_error(Statesman::TransitionFailedError)
      end
    end

    context "with a deleted update config" do
      before do
        update_job.update_config.transition_to!(:deleted)
      end

      it "cancels the update job" do
        expect(MetricsClient).to receive(:count).with(
          "update_job.cancelled", 1,
          tags: hash_including({
                                 runner_type: update_job_runner_type,
                                 cancellation_reason: "inactive_config",
                                 config_file: false,
                               })
        )
        expect_any_instance_of(runner_class).not_to receive(:run)
        job.perform_now
        expect(update_job.reload.current_state).to eq("cancelled")
      end

      it "marks the job as errored" do
        expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: {
              "error-type" => "cancelled_update",
              "error-detail" => { "cancellation-reason" => "inactive_config" },
            },
          )
      end
    end

    context "when the ecosystem is disabled" do
      before do
        repo.enable_feature(:disable_bundler_jobs) # rubocop:disable Dependabot/NoLocalFeatureFlags
      end

      it "cancels the update job" do
        expect(MetricsClient).to receive(:count).with(
          "update_job.cancelled", 1,
          tags: hash_including({
                                 update_type: "version",
                                 runner_type: update_job_runner_type,
                                 cancellation_reason: "disabled_ecosystem",
                               })
        )
        expect_any_instance_of(runner_class).not_to receive(:run)
        job.perform_now
        expect(update_job.reload.current_state).to eq("cancelled")
      end

      it "marks the job as errored" do
        expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: {
              "error-type" => "cancelled_update",
              "error-detail" => { "cancellation-reason" => "disabled_ecosystem" },
            },
          )
      end
    end

    context "with an update job that is retrying" do
      let(:update_job) do
        FactoryBot.create(
          :update_job, :pending_retry,
          update_config_id: update_config.id,
          runner_type: update_job_runner_type
        )
      end

      it "updates the update job" do
        expect { job.perform_now }.to change(update_job, :hashed_token).from(nil)
      end

      it "kicks off a bumping job" do
        expect_any_instance_of(runner_class).to receive(:run)
        perform_enqueued_jobs do
          job.perform_now
        end
      end
    end

    context "when the repo can't be found on GitHub" do
      let(:installation_repos_url) do
        github_url + "installation/repositories?per_page=100"
      end
      let(:github_repos) do
        fixture("github_responses/installation_repos.json").gsub("88632334", "88")
      end
      let(:github_installation) do
        fixture("github_responses/installation.json").
          gsub("25222", installation_id.to_s)
      end

      before do
        stub_request(:get, repo_url).to_return(status: 404)
        stub_request(:get, installation_repos_url).
          to_return(status: 200, body: github_repos, headers: json_header)
        stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
          to_return(status: 200, body: github_installation, headers: json_header)
        stub_request(
          :get,
          "#{github_url}app/installations/#{installation_id}",
        ).to_return(status: 200, body: "{}", headers: json_header)
      end

      it "sets the job up for a retry" do
        expect { job.perform_now }.to have_enqueued_job(described_class).with(update_job)
      end

      context "with an inactive account" do
        before do
          account.transition_to!(
            :inactive,
            installation_id: installation_id,
          )
          stub_request(:get, "#{github_url}app/installations/").
            to_return(status: 404)
        end

        it "cancels the update job" do
          expect { job.perform_now }.
            to change { update_job.reload.current_state }.
            to eq("cancelled")
        end
      end

      context "because of a legal issue" do
        before do
          stub_request(:get, repo_url).
            to_return(
              status: 451,
              body: fixture("github_responses/forbidden_legal_issue.json"),
            )
        end

        it "cancels the update job" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "unavailable_for_legal_reasons",
                                   config_file: false,
                                 })
          )

          expect { job.perform_now }.
            to change { update_job.reload.current_state }.
            to eq("cancelled")
        end

        it "marks the job as errored" do
          expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
            with(
              update_job: update_job,
              error_hash: {
                "error-type" => "cancelled_update",
                "error-detail" => {
                  "cancellation-reason" => "unavailable_for_legal_reasons",
                },
              },
            )
        end

        it "deletes the update_config" do
          expect { job.perform_now }.
            to change { update_config.reload.current_state }.
            to eq("deleted")
        end
      end

      context "because of trade restrictions on the repo" do
        before do
          stub_request(:get, repo_url).
            to_return(
              status: 403,
              body: fixture("github_responses/forbidden_trade_restriction.json"),
            )
        end

        it "cancels the update job" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "trade_control",
                                   config_file: false,
                                 })
          )

          expect { job.perform_now }.
            to change { update_job.reload.current_state }.
            to eq("cancelled")
        end

        it "marks the job as errored" do
          expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
            with(
              update_job: update_job,
              error_hash: {
                "error-type" => "cancelled_update",
                "error-detail" => { "cancellation-reason" => "trade_control" },
              },
            )
        end

        it "deletes the update_config" do
          expect { job.perform_now }.
            to change { update_config.reload.current_state }.
            to eq("deleted")
        end
      end

      context "because of trade restrictions on the owner" do
        before do
          stub_request(:get, repo_url).
            to_return(
              status: 403,
              body: fixture(
                "github_responses/forbidden_trade_restriction_verbose.json"
              ),
            )
        end

        it "cancels the update job" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "trade_control",
                                   config_file: false,
                                 })
          )

          expect { job.perform_now }.
            to change { update_job.reload.current_state }.
            to eq("cancelled")
        end

        it "marks the job as errored" do
          expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
            with(
              update_job: update_job,
              error_hash: {
                "error-type" => "cancelled_update",
                "error-detail" => { "cancellation-reason" => "trade_control" },
              },
            )
        end

        it "deletes the update_config" do
          expect { job.perform_now }.
            to change { update_config.reload.current_state }.
            to eq("deleted")
        end
      end

      context "because of a billing issue" do
        before do
          stub_request(:get, repo_url).
            to_return(
              status: 403,
              body: fixture("github_responses/forbidden_billing_issue.json"),
            )
        end

        it "cancels the update job" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "billing_issue",
                                   config_file: false,
                                 })
          )

          expect { job.perform_now }.
            to change { update_job.reload.current_state }.
            to eq("cancelled")
        end
      end

      context "because the installation no longer has access to the repository" do
        before do
          stub_request(:get, repo_url).
            to_return(
              status: 403,
              body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
            )
        end

        it "retries the background job" do
          expect { job.perform_now }.to have_enqueued_job(described_class).with(update_job)
        end

        it "cancels the job once retries are exhausted" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "repo_sync_installation_error",
                                   config_file: false,
                                 })
          )

          perform_enqueued_jobs do
            job.perform_now
          end

          expect(update_job.reload.current_state).to eq("cancelled")
        end

        it "instruments an intermittant error" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.repo_sync_error.retry", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                 })
          )

          job.perform_now
        end

        it "logs the error" do
          allow(Dependabot::Logger).to receive(:error)
          expect(Dependabot::Logger).to receive(:error).with(
            hash_including(
              msg: "UpdateJob raised retryable exception",
            )
          )

          job.perform_now
        end

        it "leaves the update_config active" do
          expect { job.perform_now }.
            not_to change { update_config.reload.current_state }
        end
      end

      context "when dependabot isn't installed on the repository" do
        before do
          stub_request(:post, install_access_token_url).
            to_return(
              status: 422,
              body: fixture("github_responses/repo_installation_missing.json"),
            )
        end

        it "retries the background job" do
          expect { job.perform_now }.to have_enqueued_job(described_class).with(update_job)
        end

        it "cancels the job once retries are exhausted" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "repo_sync_installation_error",
                                   config_file: false,
                                 })
          )

          perform_enqueued_jobs do
            job.perform_now
          end

          expect(update_job.reload.current_state).to eq("cancelled")
        end

        it "instruments an intermittant error" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.repo_sync_error.retry", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   update_type: "version",
                                 })
          )

          job.perform_now
        end

        it "leaves the update_config active" do
          expect { job.perform_now }.
            not_to change { update_config.reload.current_state }
        end
      end

      context "when no repository was provided" do
        before do
          stub_request(:post, install_access_token_url).
            to_return(
              status: 422,
              body: fixture("github_responses/no_repository_provided.json"),
            )
        end

        it "retries the background job" do
          expect { job.perform_now }.to have_enqueued_job(described_class).with(update_job)
        end

        it "cancels the job once retries are exhausted" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   cancellation_reason: "repo_sync_installation_error",
                                   config_file: false,
                                 })
          )

          perform_enqueued_jobs do
            job.perform_now
          end

          expect(update_job.reload.current_state).to eq("cancelled")
        end

        it "instruments an intermittant error" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.repo_sync_error.retry", 1,
            tags: hash_including({
                                   runner_type: update_job_runner_type,
                                   update_type: "version",
                                 })
          )

          job.perform_now
        end

        it "leaves the update_config active" do
          expect { job.perform_now }.
            not_to change { update_config.reload.current_state }
        end
      end
    end

    context "when the repo has been transferred" do
      let(:installation_repos_url) do
        github_url + "installation/repositories?per_page=100"
      end
      let(:github_repos) do
        fixture("github_responses/installation_repos.json").gsub("88632334", "88")
      end
      let(:github_installation) do
        fixture("github_responses/installation.json").
          gsub("25222", installation_id.to_s)
      end

      before { account.update!(github_id: 1234) }

      before do
        stub_request(:get, installation_repos_url).
          to_return(status: 200, body: github_repos, headers: json_header)
        stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
          to_return(status: 200, body: github_installation, headers: json_header)
        stub_request(
          :get,
          "#{github_url}app/installations/#{installation_id}",
        ).to_return(status: 200, body: "{}", headers: json_header)
      end

      it "resyncs the repo account and cancels the update job" do
        expect(MetricsClient).to receive(:count).with(
          "update_job.cancelled", 1,
          tags: hash_including({
                                 runner_type: update_job_runner_type,
                                 cancellation_reason: "account_out_of_sync",
                                 config_file: false,
                               })
        )

        expect { job.perform_now }.
          to have_enqueued_job(TransferRepoAccountJob).
          with(repo: update_job.update_config.repo, new_account: nil)
        expect(update_job.reload.current_state).to eq("cancelled")
      end

      it "marks the job as errored" do
        expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: {
              "error-type" => "cancelled_update",
              "error-detail" => {
                "cancellation-reason" => "account_out_of_sync",
              },
            },
          )
      end
    end

    context "when the repo has been archived" do
      let(:installation_repos_url) do
        github_url + "installation/repositories?per_page=100"
      end
      let(:github_repos) do
        fixture("github_responses/installation_repos_2.json").
          gsub("87123", "88632334")
      end
      let(:github_repo) do
        fixture("github_responses/repo.json").
          gsub('"archived": false', '"archived": true')
      end
      let(:github_installation) do
        fixture("github_responses/installation.json").
          gsub("25222", installation_id.to_s)
      end

      before do
        stub_request(:get, installation_repos_url).
          to_return(status: 200, body: github_repos, headers: json_header)
        stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
          to_return(status: 200, body: github_installation, headers: json_header)
        stub_request(
          :get,
          "#{github_url}app/installations/#{installation_id}",
        ).to_return(status: 200, body: "{}", headers: json_header)
      end

      it "deactivates the repo and cancels the update job" do
        expect(MetricsClient).to receive(:count).with(
          "update_job.cancelled", 1,
          tags: hash_including({
                                 runner_type: update_job_runner_type,
                                 cancellation_reason: "account_out_of_sync",
                                 config_file: false,
                               })
        )

        expect { job.perform_now }.
          to change { account.repos.active.count }.
          by(-1)
        expect(update_job.reload.current_state).to eq("cancelled")
      end

      it "marks the job as errored" do
        expect { job.perform_now }.to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: {
              "error-type" => "cancelled_update",
              "error-detail" => {
                "cancellation-reason" => "account_out_of_sync",
              },
            },
          )
      end
    end
  end

  context "with an UpdateJob that runs in Actions" do
    let(:runner_class) { RunUpdater::Actions }
    let(:update_job_runner_type) { UpdateJob::RUNNER_ACTIONS }
    let(:update_job_trigger_type) { "push" }

    let(:execution_id) { "75b5f5dd-870f-4a44-8068-70380837fe80" }
    let(:dynamic_workflow_url) { github_url + "repositories/#{repo.github_id}/actions/dynamic" }
    let(:internal_dynamic_workflow_url) { github_url + "internal/repositories/#{repo.github_id}/actions/dynamic" }
    let(:dynamic_workflow_status_code) { 200 }
    let(:dynamic_workflow_body) do
      {
        execution_id: execution_id,
      }.to_json
    end

    before do
      stub_request(:post, dynamic_workflow_url).to_return(
        status: dynamic_workflow_status_code,
        body: dynamic_workflow_body,
        headers: json_header
      )
      stub_request(:post, internal_dynamic_workflow_url).to_return(
        status: dynamic_workflow_status_code,
        body: dynamic_workflow_body,
        headers: json_header
      )
    end

    it_behaves_like "a fully implemented job runner"

    context "when GitHub rate limits retrieving job information" do
      before do
        stub_request(:get, repo_url).
          to_return(status: 403, body: fixture("github_responses/forbidden_rate_limited.json"), headers: json_header)
      end

      it "retries the background job" do
        expect { job.perform_now }.to have_enqueued_job(described_class).with(update_job)
      end

      it "marks the job as processed_with_errors if retries are exhausted" do
        perform_enqueued_jobs do
          job.perform_now
        end

        expect(update_job.reload.current_state).to eq("processed_with_errors")
        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql("octokit_rate_limited")
      end

      context "and the account is marked as spammy" do
        before do
          account.enable_feature(:spammy) # rubocop:disable Dependabot/NoLocalFeatureFlags
        end

        it "does not retry the update job" do
          expect { job.perform_now }.not_to have_enqueued_job(described_class).with(update_job)
        end

        it "cancels the update job" do
          expect(MetricsClient).to receive(:count).with(
            "update_job.cancelled", 1,
            tags: hash_including({
                                   runner_type: "actions",
                                   cancellation_reason: "spammy_rate_limited",
                                   config_file: false,
                                 })
          )

          expect { job.perform_now }.
            to change { update_job.reload.current_state }.from("pending").to("cancelled")
        end
      end
    end

    context "when GitHub rate limits the action creation" do
      before do
        stub_request(:get, repo_url).
          to_return(status: 200, body: github_repo, headers: json_header)
      end

      let(:dynamic_workflow_status_code) { 403 }
      let(:dynamic_workflow_body) do
        fixture("github_responses/forbidden_rate_limited.json")
      end

      it "retries the background job" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Default) # rubocop:disable RSpec/DescribedClass
      end

      it "marks the job as processed_with_errors if retries are exhausted" do
        perform_enqueued_jobs do
          job.perform_now
        end

        expect(update_job.reload.current_state).to eq("processed_with_errors")
        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql("octokit_rate_limited")
      end

      context "and the account is marked as spammy" do
        before do
          stub_request(:get, repo_url).
            to_return(status: 200, body: github_repo, headers: json_header)

          account.enable_feature(:spammy) # rubocop:disable Dependabot/NoLocalFeatureFlags
        end

        it "retries the background job" do
          expect { job.perform_now }.
            to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Default). # rubocop:disable RSpec/DescribedClass
            with(update_job)
        end

        it "marks the job as processed_with_errors if retries are exhausted" do
          perform_enqueued_jobs do
            job.perform_now
          end

          expect(update_job.reload.current_state).to eq("processed_with_errors")
          expect(update_job.update_job_errors.count).to be(1)

          job_error = update_job.update_job_errors.last
          expect(job_error.error_type).to eql("octokit_rate_limited")
        end
      end
    end

    context "when the user installation is missing" do
      before do
        stub_request(:post, install_access_token_url).
          to_return(
            status: 422,
            body: fixture("github_responses/user_installation_missing.json"),
          )
      end

      it "marks the job as processed_with_errors" do
        job.perform_now

        expect(update_job.reload.current_state).to eq("processed_with_errors")
        expect(update_job.update_job_errors.count).to be(1)

        job_error = update_job.update_job_errors.last
        expect(job_error.error_type).to eql("actions_service_unprocessable")
      end
    end

    context "when there is an unexpected exception attempting to create the job" do
      before do
        allow_any_instance_of(runner_class).to receive(:run).and_raise("oh no!")

        stub_request(:get, repo_url).
          to_return(status: 200, body: github_repo, headers: json_header)
      end

      it "marks the job as processed_with_errors" do
        expect { job.perform_now }.to change(update_job, :current_state).from("pending").to("processed_with_errors")
      end
    end

    # Retryable exceptions:
    [
      # Errors handled from default_retries_for_idempotent_jobs
      *Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES.map(&:new),
    ].each do |exception|
      context "when #{exception.class.name} is raised" do
        let(:mock_exception_handler) do
          instance_double(HandleActionsRunnerFailure, run: nil)
        end

        before do
          allow(SynchronizeRepoState).to receive(:new).and_raise(exception)
          allow(HandleActionsRunnerFailure).to receive(:new).and_return(mock_exception_handler)
        end

        it "retries" do
          expect { job.perform_now }.
            to have_enqueued_job(described_class).
            on_queue("actions_dynamic_workflow_p2")
        end

        it "delegates to HandleActionsRunnerFailure after all retries are attempted" do
          perform_enqueued_jobs { job.perform_now }

          expect(HandleActionsRunnerFailure).
            to have_received(:new).
            with(update_job: update_job, error: exception)

          expect(mock_exception_handler).to have_received(:run)
        end
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
