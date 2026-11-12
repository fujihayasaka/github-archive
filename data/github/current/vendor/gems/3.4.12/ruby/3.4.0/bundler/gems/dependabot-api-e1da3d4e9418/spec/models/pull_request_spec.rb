# frozen_string_literal: true

require "rails_helper"

RSpec.describe PullRequest, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:pull_request) { FactoryBot.build_stubbed(:pull_request) }

  describe "validations" do
    it { is_expected.to be_valid }

    describe "#github_number" do
      it "validates uniqueness scoped to repo_id" do
        first = create(:pull_request)
        second = build(:pull_request, repo: first.repo, github_number: first.github_number)

        expect(second).not_to be_valid
        expect(second.errors[:github_number]).to include("has already been taken")
      end

      it "allows multiple pending PRs" do
        first = create(:pull_request,
                       github_number: PullRequest::PENDING_PR_NUMBER,
                       head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
                       dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA)
        first.transition_to!(:pending)
        second = create(:pull_request, repo: first.repo,
                                       github_number: PullRequest::PENDING_PR_NUMBER,
                                       head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
                                       dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA)
        second.transition_to!(:pending)

        expect(second).to be_valid
      end
    end

    describe "#head_commit_sha" do
      it "is invalid with pending value" do
        pull_request.head_commit_sha = PullRequest::PENDING_COMMIT_SHA
        expect(pull_request).not_to be_valid
        expect(pull_request.errors[:head_commit_sha]).to include("is reserved")
      end
    end

    describe "#dependabot_commit_sha" do
      it "is invalid with pending value" do
        pull_request.dependabot_commit_sha = PullRequest::PENDING_COMMIT_SHA
        expect(pull_request).not_to be_valid
        expect(pull_request.errors[:dependabot_commit_sha]).to include("is reserved")
      end
    end

    context "when #pending?" do
      subject(:pull_request) do
        create(
          :pull_request,
          github_number: PullRequest::PENDING_PR_NUMBER,
          head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
          dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA,
        )
      end

      before do
        pull_request.transition_to!(:pending)
      end

      describe "#github_number" do
        it "is valid with pending value" do
          expect(pull_request).to be_pending
          expect(pull_request.github_number).to eq(PullRequest::PENDING_PR_NUMBER)
          expect(pull_request).to be_valid
        end
      end

      describe "#head_commit_sha" do
        it "is valid with pending value" do
          expect(pull_request).to be_pending
          expect(pull_request.head_commit_sha).to eq(PullRequest::PENDING_COMMIT_SHA)
          expect(pull_request).to be_valid
        end
      end

      describe "#dependabot_commit_sha" do
        it "is valid with pending value" do
          expect(pull_request).to be_pending
          expect(pull_request.dependabot_commit_sha).to eq(PullRequest::PENDING_COMMIT_SHA)
          expect(pull_request).to be_valid
        end
      end
    end
  end

  describe "transitions" do
    context "from up_to_date" do
      subject(:pull_request) { create(:pull_request) }

      it "can transition to pending" do
        expect(pull_request.current_state).to eq("up_to_date")
        expect(pull_request.transition_to(:pending)).to eq(true)
        expect(pull_request.reload.current_state).to eq("pending")
      end
    end

    context "from pending" do
      subject(:pull_request) do
        create(
          :pull_request,
          github_number: PullRequest::PENDING_PR_NUMBER,
          head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
          dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA,
        )
      end

      before do
        pull_request.transition_to!(:pending)
      end

      it "cannot transition to up_to_date when pending values have not been updated" do
        expect(pull_request.current_state).to eq("pending")
        expect(pull_request.transition_to(:up_to_date)).to eq(false)
        expect(pull_request.reload.current_state).to eq("pending")
      end

      context "when pending values have been updated" do
        before do
          pull_request.update!(
            github_number: 100,
            head_commit_sha: "deadbeef",
            dependabot_commit_sha: "deadbeef",
          )
        end

        it "can transition to up_to_date" do
          expect(pull_request.current_state).to eq("pending")
          expect(pull_request.transition_to(:up_to_date)).to eq(true)
          expect(pull_request.reload.current_state).to eq("up_to_date")
        end
      end
    end
  end

  describe ".previously_merged" do
    it "excludes pull requests that have not been merged previously" do
      FactoryBot.create(:pull_request)
      FactoryBot.create(:pull_request, :updating)
      FactoryBot.create(:pull_request, :closed)
      FactoryBot.create(:pull_request, :merged)

      expect(described_class.previously_merged).to be_empty
    end

    it "includes pull requests that have been previously merged, even if their current state does not reflect this" do
      merged_pull_request = FactoryBot.create(:pull_request, :merged)
      merged_pull_request.transition_to!(:closed)

      expect(merged_pull_request.reload.current_state).to eq("closed")
      expect(described_class.previously_merged).to contain_exactly(merged_pull_request)
    end
  end

  describe ".exclude_pending" do
    it "excludes pending prs" do
      first = create(:pull_request,
                     github_number: PullRequest::PENDING_PR_NUMBER,
                     head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
                     dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA)
      first.transition_to!(:pending)
      create(:pull_request, repo: first.repo)
      expect(described_class.exclude_pending.count).to be 1
    end
  end

  describe "#github_url" do
    subject { pull_request.github_url }

    let(:repo) { FactoryBot.build_stubbed(:repo, :bump_test) }
    let(:pull_request) do
      FactoryBot.build_stubbed(:pull_request, repo: repo, github_number: 123)
    end

    it { is_expected.to eq("https://github.com/dependabot/bump-test/pull/123") }
  end

  describe "most_recent_update_job" do
    it "returns the most recent update job when updated" do
      # :updating creates a new update job
      pull_request = FactoryBot.create(:pull_request, :updating)

      most_recent_update_job = UpdateJob.last

      # the originating update job is not the most recent
      expect(pull_request.update_job).not_to eq(most_recent_update_job)
      expect(pull_request.most_recent_update_job).to eq(most_recent_update_job)
    end

    it "returns the original update job when not updated" do
      # :updating creates a new update job
      pull_request = FactoryBot.create(:pull_request, :up_to_date)

      expect(pull_request.most_recent_update_job).to eq(pull_request.update_job)
    end
  end

  describe "#create_rebase_update_jobs" do
    subject(:pull_request) { FactoryBot.create(:pull_request, :up_to_date) }

    it "raises if not in the right state" do
      expect do
        pull_request.create_rebase_update_jobs
      end.to raise_error(RuntimeError, /invalid state/i)
    end

    it "creates a new job with a trigger type of rebase and the transition id" do
      pull_request.transition_to!(:updating)
      pull_request.create_rebase_update_jobs

      expect(UpdateJob.last.trigger_type).to eql("rebase")
      expect(UpdateJob.last.pull_request_transition_id).to eq(pull_request.pull_request_transitions.last.id)
    end

    it "carries over github_request_id from initiating pr job" do
      pr_update_job =
        FactoryBot.create(:update_job, :security, github_request_id: 1701)
      pull_request.update!(update_job: pr_update_job)
      pull_request.transition_to!(:updating)

      expect { _ = pull_request.create_rebase_update_jobs }.
        to change(UpdateJob, :count).by(1)

      rebase_update_job = UpdateJob.last
      expect(rebase_update_job.github_request_id).to eq(1701)
    end

    context "when the pull request is for a security_updates_only job" do
      let!(:update_job) { FactoryBot.create(:update_job, :security) }

      before do
        pull_request.update!(update_job: update_job)
      end

      it "carries over security_updates_only from initiating pr job" do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs

        expect(UpdateJob.last.security_updates_only).
          to eq(true)
      end
    end

    context "when the rebase was requested directly by the user" do
      it "sets a trigger type of manual_rebase" do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs(manual: true)

        expect(UpdateJob.last.trigger_type).to eql("manual_rebase")
      end
    end

    context "when the pull request affected a single directory" do
      before { pull_request.update!(affected_directories: ["foo"]) }

      it "carries over the affected directories to the UpdateJob" do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs

        expect(UpdateJob.last.directories).to eq(["foo"])
      end
    end

    context "when the pull request relates to a multi-ecosystem update" do
      let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
      let(:update_config) { create(:update_config, multi_ecosystem_config: multi_ecosystem_config) }
      let(:pull_request) { create(:pull_request, update_config: update_config) }

      it "creates update jobs with the same enqueue_scheduled_update_id" do
        # create a multi-ecosystem config sibling
        create(:update_config, package_manager: "npm_and_yarn", multi_ecosystem_config:)

        pull_request.transition_to!(:updating)
        jobs = pull_request.create_rebase_update_jobs

        expect(jobs.size).to eq(2)
        expect(jobs.first.enqueue_scheduled_update_id).to eq(jobs.second.enqueue_scheduled_update_id)

        bundler_job = jobs.find { |job| job.package_manager == "bundler" }
        expect(bundler_job.dependencies).to eq(["business"])

        npm_job = jobs.find { |job| job.package_manager == "npm_and_yarn" }
        expect(npm_job.dependencies).to eq([])
      end
    end
  end

  describe "#rebase_update_config_ids" do
    it "returns the update_config_id if it is not part of a multi-ecosystem update" do
      pull_request = create(:pull_request)
      expect(pull_request.rebase_update_config_ids).to eq([pull_request.update_config_id])
    end

    it "returns the multi_ecosystem_config_id if it is part of a multi-ecosystem update" do
      pull_request = create(:pull_request, :for_a_multi_ecosystem_update)
      create(:update_config, repo: pull_request.repo, multi_ecosystem_config: pull_request.multi_ecosystem_config)

      expected_ids = pull_request.multi_ecosystem_config.update_configs.ids

      expect(pull_request.rebase_update_config_ids).to eq(expected_ids)
    end
  end

  describe "#age_in_days" do
    context "for a brand new pull request" do
      subject(:pr) do
        FactoryBot.create(:pull_request).age_in_days
      end

      it { is_expected.to be(0) }
    end

    context "for a week old pull request" do
      subject(:pr) do
        travel_to(7.days.ago) do
          FactoryBot.create(:pull_request)
        end.age_in_days
      end

      it { is_expected.to be(7) }
    end

    context "for an ancient pull request" do
      subject(:pr) do
        travel_to(365.days.ago) do
          FactoryBot.create(:pull_request)
        end.age_in_days
      end

      it { is_expected.to be(365) }
    end

    context "for a future pull request" do
      subject(:pr) do
        travel_to(5.minutes.from_now) do
          FactoryBot.create(:pull_request)
        end.age_in_days
      end

      it { is_expected.to be(0) }
    end

    context "for a far future pull request" do
      subject(:pr) do
        travel_to(5.days.from_now) do
          FactoryBot.create(:pull_request)
        end.age_in_days
      end

      it { is_expected.to be(-5) }
    end

    context "an unpersisted pull request" do
      subject(:pr) do
        travel_to(5.days.from_now) do
          FactoryBot.build(:pull_request)
        end.age_in_days
      end

      it { is_expected.to be(0) }
    end
  end

  describe "#audit_log" do
    subject(:pull_request) do
      FactoryBot.create(:pull_request, repo: repo, update_config: update_config)
    end

    let(:update_config) { FactoryBot.create(:update_config, repo: repo) }
    let(:account) { FactoryBot.create(:account) }
    let(:repo) do
      FactoryBot.create(:repo, account: account, config_file_path: ".github/dependabot.yml")
    end

    let(:expected_repo_tags) do
      {
        account_id: repo.account.id,
        "gh.owner.id": repo.account.github_id,
        repository_id: repo.id,
        "gh.repo.id": repo.github_id,
        repository_using_config_file: true,
        nwo: repo.nwo,
        will_pause_at: repo.will_pause_at,
        paused_at: repo.paused_at,
      }
    end

    let(:expected_config_tags) do
      {
        "gh.dependabot_api.update_config.id": update_config.id,
        update_config_version_updates_enabled: true,
      }
    end

    let(:expected_pr_tags) do
      {
        context: "pull-request",
        "gh.dependabot_api.update_job.id": pull_request.update_job.id,
        "gh.dependabot_api.pull_request.id": pull_request.id,
        pull_request_github_number: pull_request.github_number,
        pull_request_head_commit_sha: pull_request.head_commit_sha,
        pull_request_dependabot_commit_sha: pull_request.dependabot_commit_sha,
        pull_request_base_commit_sha: pull_request.base_commit_sha,
        pull_request_state: pull_request.current_state,
        pull_request_github_url: pull_request.github_url,
      }
    end

    let(:expected_context_tags) do
      [
        expected_repo_tags,
        expected_config_tags,
        expected_pr_tags,
      ].reduce(:merge)
    end

    before do
      allow(Dependabot::Logger).to receive(:info)
      allow(Dependabot::Logger).to receive(:log_context).and_call_original
      allow(Activity::PauseManager).to receive(:handle_activity_log_event)
    end

    it "writes a structured info log of the event to the repository topic" do
      pull_request.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "pull-request.event-a",
          foo: "bar",
        }
      )
    end

    it "add details of the repository and account to the context" do
      pull_request.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).
        to have_received(:log_context).twice.
        with(a_hash_including(expected_context_tags))
    end

    it "notifies the Activity::PauseManager of the event" do
      pull_request.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Activity::PauseManager).
        to have_received(:handle_activity_log_event).
        with(
          "pull-request.event-a",
          a_hash_including(expected_context_tags.merge({ foo: "bar" }))
        )
    end
  end

  describe "#dependency_group" do
    let(:dependency_group) do
      create(:dependency_group, name: "my-dependencies")
    end

    context "when no dependency group is associated" do
      let(:pull_request) do
        create(:pull_request)
      end

      it "is nil" do
        expect(pull_request.dependency_group).to be_nil
      end

      it "allows grouped_update to be true or false" do
        pull_request.grouped_update = false

        expect(pull_request).to be_valid

        pull_request.grouped_update = true

        expect(pull_request).to be_valid
      end
    end

    context "when a dependency group is associated" do
      let(:pull_request) do
        create(:pull_request, dependency_group: dependency_group, grouped_update: true)
      end

      it "returns the dependency group" do
        expect(pull_request.dependency_group).to eql(dependency_group)
      end

      it "only permits the grouped_update flag to be true" do
        pull_request.grouped_update = false

        expect(pull_request).not_to be_valid

        pull_request.grouped_update = true

        expect(pull_request).to be_valid
      end
    end

    context "when a logically deleted dependency group is associated" do
      let(:pull_request) do
        create(:pull_request, dependency_group: dependency_group, grouped_update: true)
      end

      before do
        dependency_group.delete
        pull_request.reload
      end

      it "still returns the dependency group" do
        expect(pull_request.dependency_group).to eql(dependency_group)
        expect(pull_request.dependency_group).to be_deleted
      end

      it "still only permits the grouped_update flag to be true" do
        pull_request.grouped_update = false

        expect(pull_request).not_to be_valid

        pull_request.grouped_update = true

        expect(pull_request).to be_valid
      end
    end
  end

  describe "#multi_ecosystem_config" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, multi_ecosystem_config: multi_ecosystem_config) }
    let(:pull_request) do
      create(:pull_request, update_config: update_config)
    end

    it "returns the multi_ecosystem_config" do
      expect(pull_request.multi_ecosystem_config).to eq(multi_ecosystem_config)
      expect(pull_request.multi_ecosystem_config_id).to eq(multi_ecosystem_config.id)
      expect(pull_request.multi_ecosystem_config_id?).to eq(true)
    end

    it "returns nil if the update_config is not associated with a multi_ecosystem_config" do
      update_config.update!(multi_ecosystem_config: nil)

      expect(pull_request.multi_ecosystem_config).to be_nil
      expect(pull_request.multi_ecosystem_config_id).to be_nil
      expect(pull_request.multi_ecosystem_config_id?).to eq(false)
    end
  end

  describe "#create_rebase_update_jobs directory selection" do
    let(:update_config) { create(:update_config) }
    let(:pull_request) { create(:pull_request, update_config: update_config, affected_directories: %w(foo bar)) }
    let(:updated_dependencies) do
      [
        create(:updated_dependency, pull_request: pull_request, package_manager: update_config.package_manager,
                                    directory: "bundle1", name: "dep1"),
        create(:updated_dependency, pull_request: pull_request, package_manager: update_config.package_manager,
                                    directory: "bundle2", name: "dep2"),
        create(:updated_dependency, pull_request: pull_request, package_manager: PackageManagers::CARGO,
                                    directory: "cargo1", name: "dep3"),
        create(:updated_dependency, pull_request: pull_request, package_manager: update_config.package_manager,
                                    directory: "bundle3", name: "dep4"),
      ]
    end

    context "when not a multi-ecosystem update" do
      before { updated_dependencies } # ensures dependencies are created

      it "uses affected_directories" do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs
        expect(UpdateJob.last.directories).to eq(%w(foo bar))
      end
    end

    context "when a multi-ecosystem update" do
      before { updated_dependencies } # ensures dependencies are created

      let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
      let(:update_config) { create(:update_config, multi_ecosystem_config: multi_ecosystem_config) }
      let(:pull_request) { create(:pull_request, update_config: update_config) }

      it "uses unique directories from dependencies" do
        pull_request.transition_to!(:updating)
        jobs = pull_request.create_rebase_update_jobs
        expect(jobs.last.directories).to eq(%w(/ bundle1 bundle2 bundle3))
      end
    end

    context "when no dependencies are updated" do
      before do
        pull_request.updated_dependencies.clear
      end

      it "uses manifest_directories" do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs
        expect(UpdateJob.last.directories).to eq(%w(foo bar))
      end
    end
  end

  describe "#incorrectly_in_closed_state?" do
    let(:pull_request) do
      create(:pull_request)
    end

    it "identifies a PR that was merged then changed to closed" do
      pull_request.transition_to!(:merged)
      pull_request.transition_to!(:closed)
      expect(pull_request.incorrectly_in_closed_state?).to eq(true)
    end

    it "rejects a PR that was merged then changed to up_to_date before closing" do
      pull_request.transition_to!(:merged)
      pull_request.transition_to!(:up_to_date)
      pull_request.transition_to!(:closed)
      expect(pull_request.incorrectly_in_closed_state?).to eq(false)
    end

    it "rejects a PR with no transitions" do
      expect(pull_request.incorrectly_in_closed_state?).to eq(false)
    end

    it "rejects a PR that was closed without being merged" do
      pull_request.transition_to!(:closed)
      expect(pull_request.incorrectly_in_closed_state?).to eq(false)
    end
  end

  describe "#currently_updating?" do
    let(:pull_request) do
      create(:pull_request)
    end

    it "returns false if in the default state" do
      expect(pull_request.currently_updating?).to eq(false)
    end

    it "returns false if not in the updating state" do
      pull_request.transition_to!(:updating)
      pull_request.transition_to!(:up_to_date)

      expect(pull_request.currently_updating?).to eq(false)
    end

    it "returns false if it's been in the updating state for too long" do
      travel_to(4.hours.ago) do
        pull_request.transition_to!(:updating)
      end

      expect(pull_request.currently_updating?).to eq(false)
    end

    it "returns true if it's in the updating state recently" do
      pull_request.transition_to!(:updating)

      expect(pull_request.currently_updating?).to eq(true)
    end
  end

  describe "#pending?" do
    context "when unpersisted and in up_to_date state" do
      subject(:pull_request) { described_class.new }

      it "returns true" do
        expect(pull_request).not_to be_persisted
        expect(pull_request.current_state).to eq("up_to_date")
        expect(pull_request.pending?).to eq(true)
      end
    end

    context "when persisted and in up_to_date state" do
      subject(:pull_request) { create(:pull_request) }

      it "returns false" do
        expect(pull_request.current_state).to eq("up_to_date")
        expect(pull_request.pending?).to eq(false)
      end
    end

    context "when persisted and in pending state" do
      subject(:pull_request) { create(:pull_request) }

      before do
        pull_request.transition_to!(:pending)
      end

      it "returns true" do
        expect(pull_request.current_state).to eq("pending")
        expect(pull_request.pending?).to eq(true)
      end
    end

    %w(closed merged updating).each do |state|
      context "when persisted and in #{state}" do
        subject(:pull_request) { create(:pull_request) }

        before do
          pull_request.transition_to!(state)
        end

        it "returns false" do
          expect(pull_request.current_state).to eq(state)
          expect(pull_request.pending?).to eq(false)
        end
      end
    end
  end

  describe "#broke_ci?" do
    it "is true when the base commit ci is successful and dependabot commit ci fails" do
      pr = build(:pull_request, base_commit_ci_status: GitHub::CheckRun::Conclusion::SUCCESS,
                                dependabot_commit_ci_status: GitHub::CheckRun::Conclusion::FAILURE)
      expect(pr.broke_ci?).to be(true)
    end

    (GitHub::CheckRun::Conclusion.constants + [nil] - [GitHub::CheckRun::Conclusion::SUCCESS]).each do |status|
      it "is false when the base commit ci is #{status.nil? ? 'nil' : "'#{status}"}" do
        pr = build(:pull_request, base_commit_ci_status: status,
                                  dependabot_commit_ci_status: GitHub::CheckRun::Conclusion::FAILURE)
        expect(pr.broke_ci?).to be(false)
      end
    end

    (GitHub::CheckRun::Conclusion.constants + [nil] - [GitHub::CheckRun::Conclusion::FAILURE]).each do |status|
      it "is false when the dependabot commit ci is #{status.nil? ? 'nil' : "'#{status}"}" do
        pr = build(:pull_request, base_commit_ci_status: GitHub::CheckRun::Conclusion::SUCCESS,
                                  dependabot_commit_ci_status: status)
        expect(pr.broke_ci?).to be(false)
      end
    end
  end

  describe "#actions_workflow_run_id" do
    it "sets the value in redis" do
      pr = create(:pull_request)
      pr.actions_workflow_run_id = "12345"

      expect(
        Dependabot.redis.get("pr-actions-workflow-run-id:12345")
      ).to eq(pr.id.to_s)
    end
  end

  describe "#hashed_token" do
    it "returns the value stored in redis" do
      pr = create(:pull_request)
      pr.hashed_token = "12345"

      expect(pr.hashed_token).to eq("12345")
    end
  end

  describe "#autofix_candidate?" do
    let(:updated_dependencies) do
      FactoryBot.create_list(
        :updated_dependency, 1,
        package_manager: PackageManagers::NPM_AND_YARN,
        requirements: "1.2.3", previous_requirements: "1.2.0"
      )
    end

    let(:pull_request) do
      FactoryBot.create(
        :pull_request,
        base_commit_ci_status: GitHub::CheckRun::Conclusion::SUCCESS,
        dependabot_commit_ci_status: GitHub::CheckRun::Conclusion::FAILURE,
        head_commit_ci_status: GitHub::CheckRun::Conclusion::FAILURE,
        updated_dependencies: updated_dependencies
      )
    end

    before do
      stub_monolith_feature(:dependabot_autofix, enabled: true, actor: pull_request.repo.monolith_actor)
    end

    it "is true when all requirements are met" do
      expect(pull_request.autofix_candidate?).to be(true)
    end

    it "is false when the PR has not broken CI" do
      pull_request.dependabot_commit_ci_status = GitHub::CheckRun::Conclusion::SUCCESS
      expect(pull_request.autofix_candidate?).to be(false)
    end

    it "is false when the CI is not complete" do
      pull_request.head_commit_ci_status = nil
      expect(pull_request.autofix_candidate?).to be(false)
    end

    it "is false when autofix is not enabled on the PR repo" do
      stub_monolith_feature(:dependabot_autofix, actor: pull_request.repo.monolith_actor, enabled: false)
      pull_request.repo.disable_feature(:autofix_demo)
      expect(pull_request.autofix_candidate?).to be(false)
    end

    (Languages::ALL - AutofixSuggestionJob::AUTOFIX_SUPPORTED_LANGUAGES).each do |lang|
      context "when the pull request updates dependencies for #{lang}" do
        let(:updated_dependencies) do
          Ecosystems.package_managers_for_language(lang).map do |package_manager|
            FactoryBot.create(
              :updated_dependency,
              package_manager: package_manager,
              requirements: "1.2.3", previous_requirements: "1.2.0"
            )
          end
        end

        it "is false" do
          expect(pull_request.autofix_candidate?).to be(false)
        end
      end
    end

    context "when the pull request does not contain dependencies with updated requirements" do
      let(:updated_dependencies) do
        FactoryBot.create_list(
          :updated_dependency, 1,
          package_manager: PackageManagers::NPM_AND_YARN,
          requirements: "1.2.3", previous_requirements: "1.2.3"
        )
      end

      it "is false" do
        expect(pull_request.autofix_candidate?).to be(false)
      end
    end
  end
end
