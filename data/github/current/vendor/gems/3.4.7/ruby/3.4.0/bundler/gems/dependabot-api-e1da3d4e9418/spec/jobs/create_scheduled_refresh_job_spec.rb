# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateScheduledRefreshJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(pull_request: pull_request, event_source: "my-f5-key", manual: manual)
  end

  let(:repo) { FactoryBot.create(:repo, :active, github_id: 123) }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:head_commit_sha) { "1e2d2afe8320998baecdfe127a49dca9a6650e07" }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/123" }

  let(:update_config) do
    repo.update_configs.last
  end

  let(:update_job) do
    FactoryBot.create(:update_job, update_config: repo.update_configs.first)
  end

  let(:manual) { false }

  before do
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return("token")

    stub_request(:get, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)
    stub_request(:patch, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)

    allow(Dependabot::Logger).to receive(:info)

    # Ensure the full PR object graph is created before the test starts
    pull_request.touch
  end

  shared_examples "does not update the pull request" do
    it "doesn't mark the PR as updating" do
      expect { job.perform_now }.
        not_to change { pull_request.current_state(force_reload: true) }
    end

    it "does not create a new update job" do
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end

    it "does not update the pull request's description" do
      job.perform_now

      expect(WebMock).not_to have_requested(:patch, repo_url + "/pulls/1")
    end
  end

  context "when the pull request is open on GitHub" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        update_config: update_config,
        update_job: update_job,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
      )
    end

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    it "marks the PR as updating" do
      expect { job.perform_now }.
        to change { pull_request.current_state(force_reload: true) }.
        from("up_to_date").to("updating")
    end

    it "logs job start message" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "starting scheduled refresh job",
               "code.namespace": "CreateScheduledRefreshJob",
               "gh.dependabot_api.event.source": "my-f5-key",
               manual: false,
               "gh.dependabot_api.pull_request.id": pull_request.id,
               "gh.repo.id": pull_request.update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": pull_request.update_job.id,
               "gh.dependabot_api.update_config.id": pull_request.update_job.update_config.id,
               "gh.owner.id": pull_request.update_job.update_config.account.github_id,
             ))
    end

    it "logs enqueue rebase message" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "enqueuing pull request rebase",
               "code.namespace": "CreateScheduledRefreshJob",
               "gh.dependabot_api.event.source": "my-f5-key",
               manual: false,
               "gh.dependabot_api.pull_request.id": pull_request.id,
               "gh.repo.id": pull_request.update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": pull_request.update_job.id,
               "gh.dependabot_api.update_config.id": pull_request.update_job.update_config.id,
               "gh.owner.id": pull_request.update_job.update_config.account.github_id,
             ))
    end

    it "queues up a job to update the pull request" do
      expect { job.perform_now }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low) do |job|
          expect(job.update_config.repo_id).to eq(pull_request.repo_id)
          expect(job.package_manager).to eq(pull_request.update_job.package_manager)
          expect(job.dependencies).to eq(pull_request.updated_dependencies.map(&:name))
        end
    end

    it "updates the pull request's description" do
      job.perform_now

      expect(WebMock).to have_requested(:patch, repo_url + "/pulls/1")
    end

    it "creates a new UpdateJob with the correct trigger" do
      expect { job.perform_now }.to change(UpdateJob, :count).by(1)

      update_job = UpdateJob.last

      expect(update_job.trigger_type).to eql("rebase")
    end

    context "when the job is flagged as manually requested" do
      let(:manual) { true }

      it "creates a new UpdateJob with the correct trigger" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)

        update_job = UpdateJob.last

        expect(update_job.trigger_type).to eql("manual_rebase")
      end
    end
  end

  context "when the pull request is closed on GitHub" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_closed.json")
    end

    context "but the PR is update to date in Dependabot" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request, :up_to_date,
          repo: repo,
          update_config: update_config,
          update_job: update_job,
          github_number: 1,
          head_commit_sha: head_commit_sha,
          dependabot_commit_sha: head_commit_sha,
          base_commit_sha: "basecommitsha",
        )
      end

      it "enqueues a job to resync the PR" do
        expect { job.perform_now }.to have_enqueued_job(ResyncPrStateJob)
      end

      include_examples "does not update the pull request"
    end

    context "and the PR was already closed in Dependabot" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request, :closed,
          repo: repo,
          update_config: update_config,
          update_job: update_job,
          github_number: 1,
          head_commit_sha: head_commit_sha,
          dependabot_commit_sha: head_commit_sha,
          base_commit_sha: "basecommitsha",
        )
      end

      it "doesn't enqueue a job to resync" do
        expect { job.perform_now }.
          not_to have_enqueued_job(ResyncPrStateJob)
      end

      include_examples "does not update the pull request"
    end
  end

  context "the pull request is merged on GitHub" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_merged.json")
    end

    context "but the PR is update to date in Dependabot" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request, :up_to_date,
          repo: repo,
          update_config: update_config,
          update_job: update_job,
          github_number: 1,
          head_commit_sha: head_commit_sha,
          dependabot_commit_sha: head_commit_sha,
          base_commit_sha: "basecommitsha",
        )
      end

      it "enqueues a job to resync the PR" do
        expect { job.perform_now }.to have_enqueued_job(ResyncPrStateJob)
      end

      include_examples "does not update the pull request"
    end

    context "and the PR was already merged in Dependabot" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request, :merged,
          repo: repo,
          update_config: update_config,
          update_job: update_job,
          github_number: 1,
          head_commit_sha: head_commit_sha,
          dependabot_commit_sha: head_commit_sha,
          base_commit_sha: "basecommitsha",
        )
      end

      it "doesn't enqueue a job to resync" do
        expect { job.perform_now }.
          not_to have_enqueued_job(ResyncPrStateJob)
      end

      include_examples "does not update the pull request"
    end
  end

  context "the Dependabot account is inactive" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        update_config: update_config,
        update_job: update_job,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
      )
    end

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    before do
      current_installation_id = repo.account.current_installation_id
      repo.account.transition_to!(
        :inactive,
        installation_id: current_installation_id,
      )
    end

    include_examples "does not update the pull request"

    it "logs account inactive message" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "starting scheduled refresh job",
               "code.namespace": "CreateScheduledRefreshJob",
             ))

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "skipping scheduled refresh for inactive account",
               "code.namespace": "CreateScheduledRefreshJob",
             ))
    end
  end

  context "with a grouped update pull request" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        update_config: update_config,
        update_job: update_job,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
        grouped_update: true,
        dependency_group: dependency_group
      )
    end

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    context "and the dependency group is active" do
      let(:dependency_group) { FactoryBot.create(:dependency_group, :active) }

      it "updates the pull request's description" do
        job.perform_now

        expect(WebMock).to have_requested(:patch, repo_url + "/pulls/1")
      end

      it "creates a new UpdateJob with the correct trigger" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)

        update_job = UpdateJob.last

        expect(update_job.trigger_type).to eql("rebase")
      end
    end

    context "and the dependency group is logically deleted" do
      let(:dependency_group) { FactoryBot.create(:dependency_group, :deleted) }

      include_examples "does not update the pull request"

      it "queues a job to close the pull request instead" do
        expect { job.perform_now }.to have_enqueued_job(ClosePullRequestJob).with(
          pull_request: pull_request,
          reason: "dependency_group_deleted"
        )
      end

      it "logs stale group detection and enqueuing close PR job" do
        job.perform_now

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: "stale dependency group detected",
                 "code.namespace": "CreateScheduledRefreshJob",
                 dependency_group_active: false,
               ))

        expect(Dependabot::Logger).
          to have_received(:info).
          with(a_hash_including(
                 msg: "enqueuing close pull request job for stale group",
                 "code.namespace": "CreateScheduledRefreshJob",
                 reason: "dependency_group_deleted",
               ))
      end
    end

    context "and the dependency group is missing" do
      let(:dependency_group) { nil }

      include_examples "does not update the pull request"

      it "queues a job to close the pull request instead" do
        expect { job.perform_now }.to have_enqueued_job(ClosePullRequestJob).with(
          pull_request: pull_request,
          reason: "dependency_group_deleted"
        )
      end
    end
  end

  context "with a multi-ecosystem update pull request" do
    let(:pull_request) { create(:pull_request, :for_a_multi_ecosystem_update, repo:, github_number: 1) }

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    it "creates a new UpdateJob with the correct trigger" do
      expect { job.perform_now }.to change(UpdateJob, :count).by(1)

      update_job = UpdateJob.last

      expect(update_job.trigger_type).to eql("rebase")
    end
  end
end
