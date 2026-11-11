# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnqueueRebase do
  include ActiveSupport::Testing::TimeHelpers

  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      github_details: github_details,
      overwrite_edits: overwrite_edits,
      manual: manual,
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/#{pull_request.repo.github_id}/" }
  let(:pr_url) { repo_url + "pulls/#{pull_request.github_number}" }
  let(:github_pr_data) do
    fixture("github_responses/pull_request_mergeable.json")
  end

  let(:pull_request) { FactoryBot.create(:pull_request, github_number: 21) }
  let(:overwrite_edits) { false }
  let(:manual) { false }
  let(:github_details) do
    stub_request(:get, pr_url).
      to_return(status: 200, body: github_pr_data, headers: json_header)
    Octokit::Client.new(
      access_token: "junk",
      api_endpoint: github_url
    ).
      pull_request(pull_request.repo.github_id, pull_request.github_number)
  end
  let(:repo_synchronizer_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_synchronizer) { double(run: repo_synchronizer_result) }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:patch, pr_url)
    allow(SynchronizeRepoState).
      to receive(:new).
      with(repo: pull_request.repo,
           event_source: anything).
      and_return(dummy_repo_synchronizer)
    allow(MetricsClient).to receive(:increment)
  end

  it "transitions the PR and updates its description on GitHub" do
    expect { action.run }.
      to change { pull_request.current_state(force_reload: true) }.
      to("updating")
    expect(WebMock).to have_requested(:patch, pr_url)
  end

  it "adds the job to the transition" do
    action.run
    expect(pull_request.last_transition.update_job).to be_present
  end

  it "enqueues an update job" do
    expect { action.run }.
      to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
      with(instance_of(UpdateJob))
  end

  it "does not instrument compute reduction" do
    action.run
    expect(MetricsClient).not_to have_received(:increment).with("compute_reduction", anything)
  end

  it "records a trace" do
    allow(action.tracer).to receive(:in_span).and_call_original
    action.run
    expect(action.tracer).to have_received(:in_span).with("EnqueueRebase#run")
  end

  context "when the pull request was updated less than 3h ago" do
    before do
      travel_to(2.hours.ago) do
        pull_request.transition_to!(:updating)
      end
    end

    it "quietly ignores the request" do
      expect { action.run }.
        to not_change { pull_request.current_state(force_reload: true) }
      expect(WebMock).not_to have_requested(:patch, pr_url)
    end

    it "does not enqueue an update job" do
      expect { action.run }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end
  end

  context "when the pull request was updated more than 3h ago" do
    before do
      travel_to(4.hours.ago) do
        pull_request.transition_to!(:updating)
      end
    end

    it "transitions the PR and updates its description on GitHub" do
      action.run
      states = pull_request.pull_request_transitions.map(&:to_state)
      expect(states).to eq(%w(updating up_to_date updating))
      expect(WebMock).to have_requested(:patch, pr_url)
    end

    it "enqueues an update job" do
      expect { action.run }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(instance_of(UpdateJob))
    end
  end

  context "but the old PR is locked" do
    let(:locked) { fixture("github_responses/forbidden_locked.json") }

    before do
      stub_request(:patch, pr_url).
        to_return(status: 403, body: locked, headers: json_header)
    end

    it "quietly ignores the request" do
      expect(pull_request.current_state(force_reload: true)).to eq("up_to_date")

      action.run

      expect(WebMock).to have_requested(:patch, pr_url)
      expect(pull_request.current_state(force_reload: true)).to eq("up_to_date")
      expect(pull_request.last_transition.update_job).to be_nil
    end

    it "does not enqueue an update job" do
      expect { action.run }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end
  end

  context "but the installation no longer has access to the repository's pull requests" do
    let(:forbidden) { fixture("github_responses/forbidden_unavailable_to_integration.json") }
    let(:github_repo) { fixture("github_responses/repo.json") }

    before do
      pull_request.repo.update!(private: false)
      stub_request(:patch, pr_url).
        to_return(status: 403, body: forbidden, headers: json_header)
      stub_request(:get, "https://github.com/hmarr").
        to_return(status: 200, body: github_repo, headers: json_header)
    end

    it "resyncs the repo state" do
      expect(dummy_repo_synchronizer).to receive(:run)

      action.run
    end
  end

  context "when the update config has been deleted" do
    before do
      pull_request.update_config.transition_to!(:deleted)
    end

    it "does not change the state of the PullRequest or modify it on GitHub" do
      expect { action.run }.
        not_to change { pull_request.current_state(force_reload: true) }.
        from("up_to_date")
      expect(WebMock).not_to have_requested(:patch, pr_url)
    end
  end

  context "when the repository is paused", feature: :inactivity_pausing do
    before do
      pull_request.repo.update!(paused_at: 1.minute.ago)
    end

    it "does not change the state of the PullRequest or modify it on GitHub" do
      expect { action.run }.
        not_to change { pull_request.current_state(force_reload: true) }.
        from("up_to_date")
      expect(WebMock).not_to have_requested(:patch, pr_url)
    end

    it "does not enqueue the actual rebase job" do
      expect { action.run }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end

    context "if the rebase was requested manually by a user" do
      let(:manual) { true }

      it "transitions the PR and updates its description on GitHub" do
        expect { action.run }.
          to change { pull_request.current_state(force_reload: true) }.
          to("updating")
        expect(WebMock).to have_requested(:patch, pr_url)
      end

      it "enqueues a high priority update job" do
        expect { action.run }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
          with(instance_of(UpdateJob))
      end
    end

    context "when the PR is stuck in the 'updating' state" do
      before do
        travel_to(3.days.ago) { pull_request.transition_to!(:updating) }
      end

      it "still fixes the state to 'up-to-date'" do
        expect { action.run }.
          to change { pull_request.current_state(force_reload: true) }.
          from("updating").
          to("up_to_date")
      end
    end
  end

  context "when the pull request is for a grouped update" do
    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        :up_to_date,
        :for_a_grouped_update,
      )
    end

    it "transitions the PR and updates its description on GitHub" do
      expect { action.run }.
        to change { pull_request.current_state(force_reload: true) }.
        to("updating")
      expect(WebMock).to have_requested(:patch, pr_url)
    end

    it "enqueues an update job" do
      expect { action.run }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(instance_of(UpdateJob))
    end
  end

  context "when updating the pull request description fails" do
    let(:update_pr_body) { instance_double(UpdatePullRequestBody, run: false) }

    before do
      allow(UpdatePullRequestBody).to receive(:new).and_return(update_pr_body)
    end

    it "deletes any created jobs and resets the transition" do
      expect { action.run }.
        not_to change { pull_request.current_state(force_reload: true) }.
        from("up_to_date")
    end

    it "deletes any created jobs" do
      expect { action.run }.not_to change { pull_request.repo.update_jobs.size }
    end

    it "does not enqueue any update jobs" do
      expect { action.run }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end

    context "when deleting pending jobs" do
      let(:jobs) { instance_double(ActiveRecord::Relation, all?: true, blank?: false) }

      before do
        allow(pull_request).to receive(:create_rebase_update_jobs).and_return(jobs)
      end

      it "calls delete_all on the jobs collection" do
        expect(jobs).to receive(:delete_all)
        action.run
      end
    end
  end
end
