# frozen_string_literal: true

require "rails_helper"

RSpec.describe CheckPullRequestForConflictsJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) do
    described_class.new(pull_request: pr, event_source: event_source, manual: manual)
  end

  let(:repo) { FactoryBot.create(:repo, :active, github_id: 123) }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:head_commit_sha) { "1e2d2afe8320998baecdfe127a49dca9a6650e07" }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/123" }

  let(:event_source) { "unknown" }
  let(:manual) { false }

  before do
    allow(GitHubHelpers).
      to receive(:access_token_for).
      and_return("token")

    stub_request(:get, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)
    stub_request(:patch, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)

    allow(Dependabot::Logger).to receive(:info)
  end

  shared_examples "updates the pull request" do
    it "marks the PR as updating" do
      expect { job.perform_now }.
        to change { pr.reload.current_state }.
        from("up_to_date").to("updating")

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "enqueuing pull request rebase",
               "code.namespace": "CheckPullRequestForConflictsJob",
               "gh.dependabot_api.event.source": event_source,
               "gh.dependabot_api.pull_request.id": pr.id,
               "gh.repo.id": pr.update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": pr.update_job.id,
               "gh.dependabot_api.update_config.id": pr.update_job.update_config.id,
               "gh.owner.id": pr.update_job.update_config.account.github_id,
             ))
    end

    it "queues up a job to update the pull request" do
      expect { job.perform_now }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with do |job|
          expect(job.update_config.repo_id).to eq(pr.repo_id)
          expect(job.package_manager).to eq(pr.update_job.package_manager)
          expect(job.dependencies).to eq(pr.updated_dependencies.map(&:name))
        end
    end

    it "updates the pull request's description" do
      job.perform_now
      expect(WebMock).to have_requested(:patch, repo_url + "/pulls/1")
    end

    context "when the job is flagged as manually requested" do
      let(:manual) { true }

      it "queues up a high priority job to update the pull request" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
          with do |job|
            expect(job.update_config.repo_id).to eq(pr.repo_id)
            expect(job.package_manager).to eq(pr.update_job.package_manager)
            expect(job.dependencies).to eq(pr.updated_dependencies.map(&:name))
          end
      end
    end
  end

  shared_examples "does not update the pull request" do
    it "doesn't mark the PR as updating" do
      expect { job.perform_now }.
        not_to change { pr.reload.current_state }
    end

    it "does not create a new update job" do
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end

    it "does not update the pull request's description" do
      job.perform_now
      expect(WebMock).not_to have_requested(:patch, repo_url + "/pulls/1")
    end
  end

  context "with an inactive account" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    let!(:pr) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
      )
    end

    before do
      current_installation_id = repo.account.current_installation_id
      repo.account.transition_to!(
        :inactive,
        installation_id: current_installation_id,
      )
    end

    it "doesn't mark the PR as updating" do
      expect { job.perform_now }.
        not_to change { pr.reload.current_state }
    end

    it "does not create a new update job" do
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end
  end

  context "for a PR that can't be fetched" do
    before { stub_request(:get, repo_url + "/pulls/1").to_return(status: 404) }

    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end

    let!(:pr) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        github_number: 1,
        head_commit_sha: "not-github",
        dependabot_commit_sha: "not-github",
      )
    end

    before do
      result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
      )
      dummy_repo_synchronizer = double(run: result)
      expect(SynchronizeRepoState).
        to receive(:new).with(
          repo: pr.repo,
          event_source: "job.check_pull_request_for_conflicts"
        ).and_return(dummy_repo_synchronizer)

      expect(dummy_repo_synchronizer).to receive(:run)
    end

    include_examples "does not update the pull request"
  end

  context "for an edited PR" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end
    let!(:pr) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        github_number: 1,
        head_commit_sha: "not-github",
        dependabot_commit_sha: "not-github",
      )
    end
    let(:commits_body) { fixture("github_responses/commits_edited.json") }

    before do
      stub_request(:get, repo_url + "/pulls/1/commits").
        to_return(status: 200, body: commits_body, headers: json_header)
    end

    include_examples "does not update the pull request"

    context "when the PR now has no commits (rare, but this happens)" do
      let(:commits_body) { "[]" }

      include_examples "does not update the pull request"
    end
  end

  context "for a PR that is already updating" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end
    let!(:pr) do
      FactoryBot.create(
        :pull_request, :updating,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
      )
    end

    include_examples "does not update the pull request"
  end

  context "for an unedited PR" do
    let!(:pr) do
      FactoryBot.create(
        :pull_request, pr_state,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: base_commit_sha,
      )
    end
    let(:pr_state) { :up_to_date }
    let(:base_commit_sha) { "basecommitsha" }

    context "that is mergeable" do
      let(:github_pull_request) do
        fixture("github_responses/pull_request_mergeable.json")
      end
      let(:comparison) { fixture("github_responses/commit_compare.json") }
      let(:ref) { "8275792d558bc3d9e7a4913aa21a1e3ffae6fab5" }

      before do
        stub_request(:get, repo_url + "/compare/#{ref}...master").
          to_return(status: 200, body: comparison, headers: json_header)
        stub_request(:get, repo_url + "/compare/#{ref}...master").
          to_return(status: 200, body: comparison, headers: json_header)
      end

      context "but is too old and can be ignored" do
        before do
          stub_request(:patch, pr_url)
          pr.update!(created_at: 31.days.ago)
        end

        let(:pr_url) { repo_url + "/pulls/#{pr.github_number}" }
        let(:event_source) { "hydro.repository_push" }

        it "doesn't mark the PR as updating" do
          expect { job.perform_now }.
            not_to change { pr.reload.current_state }
        end

        it "does not create a new update job" do
          expect { job.perform_now }.not_to change(UpdateJob, :count)
        end

        it "updates the PR body with a message" do
          job.perform_now

          expect(WebMock).to have_requested(:patch, pr_url).with(
            body: hash_including(body: /Automatic rebases have been disabled/)
          )
        end

        context "when there is already a message stating rebasing is disabled" do
          let(:github_pull_request) do
            fixture("github_responses/pull_request_no_automatic_rebases.json")
          end

          it "does not update the PR body" do
            job.perform_now

            expect(WebMock).not_to have_requested(:patch, pr_url).with(
              body: hash_including(body: /Automatic rebases have been disabled/)
            )
          end
        end

        context "when the pull request has no description (nil body)" do
          let(:github_pull_request) do
            JSON.parse(fixture("github_responses/pull_request_mergeable.json")).
              merge("body" => nil).to_json
          end

          it "does not raise a TypeError" do
            expect { job.perform_now }.not_to raise_error
          end
        end
      end

      context "with changes to the relevant dependency files" do
        before { pr.updated_dependencies.first.update!(name: "rails") }

        include_examples "updates the pull request"

        context "when there are dependencies with mixed-case names" do
          let(:comparison) do
            fixture("github_responses/pull_request_mixed_case_compare.json")
          end

          before do
            pr.updated_dependencies.first.update!(name: "flask-sqlalchemy")
            pr.update_config.update!(package_manager: "pip")
          end

          include_examples "updates the pull request"
        end

        context "when the account has automatic rebases disabled" do
          let(:repo) do
            FactoryBot.create(
              :repo, :active,
              github_id: 123,
              account: account,
            )
          end
          let(:account) do
            FactoryBot.create(
              :account, :active
            )
          end

          before do
            pr.update_config.update!(rebase_strategy: "disabled")
          end

          include_examples "does not update the pull request"

          context "but the PR has had a merge requested" do
            before { pr.update!(merge_requested: true) }

            include_examples "updates the pull request"
          end
        end
      end

      context "with changes to relevant actions workflow files" do
        let(:update_config) do
          FactoryBot.create(
            :update_config, :active,
            package_manager: "github_actions",
          )
        end
        let!(:pr) do
          FactoryBot.create(
            :pull_request, pr_state,
            repo: repo,
            update_config: update_config,
            github_number: 1,
            head_commit_sha: head_commit_sha,
            dependabot_commit_sha: head_commit_sha,
            base_commit_sha: base_commit_sha,
          )
        end

        before do
          pr.updated_dependencies.first.update!(name: "actions/setup-node")
        end

        include_examples "updates the pull request"
      end

      context "with no changes to the relevant dependency files" do
        before { pr.updated_dependencies.first.update!(name: "unchanged") }

        include_examples "does not update the pull request"
      end
    end

    context "that is behind" do
      let(:github_pull_request) do
        fixture("github_responses/pull_request_behind.json")
      end

      include_examples "updates the pull request"
    end

    context "that has an unknown mergeable state" do
      let(:github_pull_request) do
        fixture("github_responses/pull_request_unknown.json")
      end

      it "re-enqueues itself to try again later" do
        expect { job.perform_now }.to have_enqueued_job(described_class).
          with(pull_request: pr, mergeable_retries: 1, event_source: "unknown", manual: false)
      end

      context "when the mergeable retries limit is reached" do
        subject(:job) do
          limit = described_class::MERGEABLE_RETRY_LIMIT
          described_class.new(pull_request: pr, mergeable_retries: limit + 1)
        end

        it "doesn't re-enqueues itself" do
          expect { job.perform_now }.not_to have_enqueued_job(described_class)
        end
      end
    end

    context "that is not mergeable" do
      let(:github_pull_request) do
        fixture("github_responses/pull_request_dirty.json")
      end

      include_examples "updates the pull request"

      it "does not comment on the old commit" do
        job.perform_now
        expect(WebMock).not_to have_requested(
          :post,
          repo_url + "/commits/#{head_commit_sha}/comments",
        )
      end

      context "when there is a race" do
        before do
          pr.transition_to!(:updating)
          allow_any_instance_of(PullRequest).
            to receive(:in_state?).and_return(false)
        end

        include_examples "does not update the pull request"
      end

      context "because it is closed" do
        let(:github_pull_request) do
          fixture("github_responses/pull_request_closed.json")
        end

        it "enqueues a job to resync the PR" do
          expect { job.perform_now }.to have_enqueued_job(ResyncPrStateJob)
        end

        context "and the PR was already marked as closed" do
          let(:pr_state) { :closed }

          it "doesn't enqueue a job to resync" do
            expect { job.perform_now }.
              not_to have_enqueued_job(ResyncPrStateJob)
          end
        end

        include_examples "does not update the pull request"
      end

      context "because it is merged" do
        let(:github_pull_request) do
          fixture("github_responses/pull_request_merged.json")
        end

        it "enqueues a job to resync the PR" do
          expect { job.perform_now }.to have_enqueued_job(ResyncPrStateJob)
        end

        context "and the PR was already marked as merged" do
          let(:pr_state) { :merged }

          it "doesn't enqueue a job to resync" do
            expect { job.perform_now }.
              not_to have_enqueued_job(ResyncPrStateJob)
          end
        end

        include_examples "does not update the pull request"
      end

      context "when the PR is uneditted and mergable but the diff generation failed" do
        let!(:pr) do
          travel_to(42.days.ago) do
            FactoryBot.create(
              :pull_request, pr_state,
              repo: repo,
              github_number: 1,
              head_commit_sha: head_commit_sha,
              dependabot_commit_sha: head_commit_sha,
              base_commit_sha: base_commit_sha,
            )
          end
        end
        let(:pr_state) { :up_to_date }
        let(:base_commit_sha) { "basecommitsha" }

        let(:github_pull_request) do
          fixture("github_responses/pull_request_mergeable.json")
        end
        let(:ref) { "8275792d558bc3d9e7a4913aa21a1e3ffae6fab5" }

        before do
          stub_request(:get, repo_url + "/compare/#{ref}...master").
            to_return(status: 422, body: error_body, headers: json_header)
        end

        context "the diff took too long to generate" do
          let(:error_body) { fixture("github_responses/commit_compare_took_too_long.json") }

          it "doesn't enqueue a job to resync" do
            expect { job.perform_now }.
              not_to have_enqueued_job(ResyncPrStateJob)
          end
        end

        context "the diff failed for a non-specific reasons" do
          let(:error_body) { fixture("github_responses/error_generic.json") }

          it "raises an Octokit exception" do
            expect { job.perform_now }.to raise_error(Octokit::UnprocessableEntity)
          end
        end
      end
    end
  end

  context "for a grouped update pr with relevant changes on github", feature: :grouped_update_prototype do
    let!(:pr) do
      FactoryBot.create(
        :pull_request, pr_state,
        :for_a_grouped_update,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: base_commit_sha,
      )
    end
    let(:pr_state) { :up_to_date }
    let(:base_commit_sha) { "basecommitsha" }

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end
    let(:comparison) { fixture("github_responses/commit_compare.json") }
    let(:ref) { "8275792d558bc3d9e7a4913aa21a1e3ffae6fab5" }

    before do
      stub_request(:get, repo_url + "/compare/#{ref}...master").
        to_return(status: 200, body: comparison, headers: json_header)
      stub_request(:get, repo_url + "/compare/#{ref}...master").
        to_return(status: 200, body: comparison, headers: json_header)
      pr.updated_dependencies.first.update!(name: "rails")
    end

    include_examples "updates the pull request"
  end

  context "when logging conflict check" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end

    let!(:pr) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
      )
    end

    before do
      stub_monolith_feature(:dependabot_log_check_pull_request_for_conflicts, actor: repo.monolith_actor,
                                                                              enabled: true)
    end

    it "logs the conflict check with telemetry attributes" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "checking for pr conflicts",
               "code.namespace": "CheckPullRequestForConflictsJob",
               "gh.dependabot_api.event.source": event_source,
               attempt: 0,
               "gh.dependabot_api.pull_request.id": pr.id,
             ))
    end
  end

  describe "debounce / enqueue locking" do
    include LockingJobHelpers

    let!(:pr) do
      FactoryBot.create(
        :pull_request, :up_to_date,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: "basecommitsha",
      )
    end

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    after do
      clear_job_locks(described_class)
    end

    context "when the debounce feature flag is enabled" do
      before do
        allow(pr.repo).to receive(:monolith_feature_enabled?).
          with(:dependabot_debounce_conflict_checks, use_cache: true).
          and_return(true)
        allow(described_class).to receive(:debounce_enabled_for?).and_return(true)
      end

      it "does not enqueue more than one job for the same PR" do
        expect do
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
        end.to change(enqueued_jobs, :size).by(1)
      end

      it "enqueues jobs for different PRs" do
        pr2 = FactoryBot.create(
          :pull_request, :up_to_date,
          repo: repo,
          github_number: 2,
          head_commit_sha: head_commit_sha,
          dependabot_commit_sha: head_commit_sha,
          base_commit_sha: "basecommitsha",
        )

        expect do
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
          described_class.enqueue_with_debounce(pull_request: pr2, event_source: "hydro.repository_push")
        end.to change(enqueued_jobs, :size).by(2)
      end

      it "schedules with the debounce delay" do
        freeze_time do
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
          expect(Time.parse(enqueued_jobs.last["scheduled_at"]).utc).to eq(described_class::DEBOUNCE_PERIOD.from_now)
        end
      end
    end

    context "when the debounce feature flag is disabled" do
      before do
        allow(described_class).to receive(:debounce_enabled_for?).and_return(false)
      end

      it "enqueues all jobs (no deduplication)" do
        expect do
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
          described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
        end.to change(enqueued_jobs, :size).by(2)
      end

      it "does not schedule with a debounce delay" do
        described_class.enqueue_with_debounce(pull_request: pr, event_source: "hydro.repository_push")
        expect(enqueued_jobs.last["scheduled_at"]).to be_nil
      end
    end
  end
end
