# frozen_string_literal: true

require "rails_helper"
require "support/monolith_feature_flag_helper"
require "dependabot/experiment"

RSpec.describe UpdateJob, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  include MonolithSettingsHelper

  subject(:update_job) { FactoryBot.build_stubbed(:update_job) }

  let(:cooldown_metric) do
    {
      "cooldown.package_manager" => "bundler",
      "cooldown.default_days" => 7,
      "cooldown.semver_major_days" => 0,
      "cooldown.semver_minor_days" => 0,
      "cooldown.semver_patch_days" => 0,
    }
  end

  let(:multi_ecosystem_metric) { false }

  it { is_expected.to be_valid }

  describe "create hooks" do
    let(:config) do
      FactoryBot.create(:update_config)
    end

    %w(
      unknown
      manual
      install
      scan
      push
      rebase
    ).each do |trigger|
      context "an update created by a trigger of '#{trigger}'" do
        it "does not update the config's last scheduled update" do
          expect(config.last_scheduled_job_id).to be_nil

          FactoryBot.create(:update_job,
                            update_config: config,
                            trigger_type: trigger)

          expect(config.reload.last_scheduled_job_id).to be_nil
        end
      end
    end

    context "an update created by a trigger of 'scheduled'" do
      it "sets itself as the config's last scheduled update" do
        expect(config.last_scheduled_job_id).to be_nil

        job_a = FactoryBot.create(:update_job,
                                  update_config: config,
                                  trigger_type: "schedule")

        expect(config.reload.last_scheduled_job_id).to eql(job_a.id)

        job_b = FactoryBot.create(:update_job,
                                  update_config: config,
                                  trigger_type: "schedule")

        expect(config.reload.last_scheduled_job_id).to eql(job_b.id)
      end
    end
  end

  describe "#trigger_type" do
    it "is unknown by default" do
      expect(described_class.new.trigger_type).to eql("unknown")
    end
  end

  describe "#runner_type" do
    subject(:update_job) { update_config.update_jobs.create! }

    let(:repo) { FactoryBot.create(:repo) }
    let(:update_config) { FactoryBot.create(:update_config, repo: repo) }

    it "is actions by default", :cloud do
      expect(update_job.runner_type).to eql("actions")
    end

    it "permits the default to be overriden when created", :cloud do
      job = update_config.update_jobs.create!(runner_type: "actions")

      expect(job.runner_type).to eql("actions")
    end

    it "is actions by default", :enterprise do
      expect(update_job.runner_type).to eql("actions")
    end

    it "is actions by default", :proxima do
      expect(update_job.runner_type).to eql("actions")
    end

    context "for a public repo" do
      let(:repo) { FactoryBot.create(:repo, :public) }

      it "is actions by default on GHES", :enterprise do
        expect(update_job.runner_type).to eql("actions")
      end

      it "is actions by default on Proxima", :proxima do
        expect(update_job.runner_type).to eql("actions")
      end

      context "self-hosted opted in" do
        let(:repo_settings) { OpenStruct.new(dependabot_self_hosted_enabled: true) }

        it "uses self hosted if the customer has opted in to self-hosted", :cloud do
          update_job.set_runner_type(repository_settings: repo_settings)

          expect(update_job.runner_type).to eql("actions_self_hosted")
        end
      end
    end
  end

  describe "processing_errors" do
    subject { update_job.processing_errors }

    context "in state 'processed'" do
      let(:update_job) { FactoryBot.create(:update_job, :processed) }

      it { is_expected.to eq([]) }
    end

    context "in state 'processed_with_errors'" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processed_with_errors)
      end
      let(:error_hash) do
        { "error-type" => "dependency_file_not_evaluatable" }
      end

      it { is_expected.to eq([error_hash]) }
    end
  end

  describe "#increment_metric" do
    let(:instrumented_job) do
      config = FactoryBot.create(:update_config,
                                 package_manager: "bundler")

      config.update!(update_config_cooldown: UpdateConfigCooldown.new({ default_days: 7 }))

      FactoryBot.create(:update_job,
                        update_config: config,
                        trigger_type: :install,
                        metrics_metadata: { "package_managers" => { "bundler" => "2" } }.to_json)
    end
    let(:runner_type) { "actions" }
    let(:cooldown_metric) do
      {
        "cooldown.package_manager" => "bundler",
        "cooldown.default_days" => 7,
        "cooldown.semver_major_days" => 0,
        "cooldown.semver_minor_days" => 0,
        "cooldown.semver_patch_days" => 0,
      }
    end

    before do
      allow(MetricsClient).to receive(:count)
    end

    it "increments the given metric with default tags" do
      instrumented_job.increment_metric("foos")

      expect(MetricsClient).to have_received(:count).
        with("foos", 1,
             tags: {
               trigger: "install",
               package_manager: "bundler",
               update_type: "version",
               runner_type: runner_type,
               cooldown: cooldown_metric,
               multi_ecosystem_update: multi_ecosystem_metric,
               grouped_update: false,
               group_count: 0,
             })
    end

    it "appends any additional tags to defaults" do
      instrumented_job.increment_metric("foos", tags: { bar: "baz" })

      expect(MetricsClient).to have_received(:count).
        with("foos", 1,
             tags: {
               trigger: "install",
               package_manager: "bundler",
               bar: "baz",
               update_type: "version",
               runner_type: runner_type,
               cooldown: cooldown_metric,
               multi_ecosystem_update: multi_ecosystem_metric,
               grouped_update: false,
               group_count: 0,
             })
    end

    it "default tags may be overridden" do
      instrumented_job.increment_metric("foos", tags: { package_manager: "unknown" })

      expected_tags = {
        trigger: "install",
        package_manager: "unknown",
        update_type: "version",
        runner_type: runner_type,
        cooldown: cooldown_metric,
        multi_ecosystem_update: multi_ecosystem_metric,
        grouped_update: false,
        group_count: 0,
      }

      expect(MetricsClient).to have_received(:count).with("foos", 1, tags: expected_tags)
    end

    context "with a multi-ecosystem update" do
      before do
        allow(instrumented_job).to receive(:multi_ecosystem_update?).and_return(true)
      end

      let(:multi_ecosystem_metric) { true }

      it "increments the given metric with multi_ecosystem metic tags" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).to have_received(:count).
          with("foos", 1,
               tags: {
                 trigger: "install",
                 package_manager: "bundler",
                 update_type: "version",
                 runner_type: runner_type,
                 cooldown: cooldown_metric,
                 multi_ecosystem_update: multi_ecosystem_metric,
                 grouped_update: false,
                 group_count: 0,
               })
      end
    end

    context "with a security update" do
      let(:instrumented_job) do
        FactoryBot.create(:update_job,
                          trigger_type: :install,
                          security_updates_only: true)
      end

      it "increments the given metric with the defaults" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).to have_received(:count).
          with("foos", 1,
               tags: {
                 trigger: "install",
                 package_manager: "bundler",
                 update_type: "security",
                 runner_type: runner_type,
                 cooldown: {},
                 multi_ecosystem_update: multi_ecosystem_metric,
                 grouped_update: false,
                 group_count: 0,
               })
      end
    end

    context "with a graph update" do
      let(:instrumented_job) do
        FactoryBot.create(:update_job, trigger_type: :graph, command: :graph)
      end

      it "increments the given metric with the defaults" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).to have_received(:count).
          with("foos", 1,
               tags: {
                 trigger: "graph",
                 package_manager: "bundler",
                 update_type: "graph",
                 runner_type: runner_type,
                 cooldown: {},
                 multi_ecosystem_update: multi_ecosystem_metric,
                 grouped_update: false,
                 group_count: 0,
               })
      end
    end

    context "with a dry run job" do
      let(:instrumented_job) do
        FactoryBot.create(:update_job,
                          trigger_type: :install,
                          dry_run: true)
      end

      it "does not report the metric" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).not_to have_received(:count).with("foos", 1, tags: anything)
      end
    end

    context "with a grouped update" do
      let(:dependency_group) { FactoryBot.create(:dependency_group, name: "test-group") }
      let(:grouped_update_config) { FactoryBot.create(:update_config, dependency_groups: [dependency_group]) }
      let(:instrumented_job) do
        FactoryBot.create(:update_job,
                          update_config: grouped_update_config,
                          trigger_type: :install)
      end

      it "increments the given metric with group tags" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).to have_received(:count).
          with("foos", 1,
               tags: {
                 trigger: "install",
                 package_manager: "bundler",
                 update_type: "version",
                 runner_type: runner_type,
                 cooldown: {},
                 multi_ecosystem_update: false,
                 grouped_update: true,
                 group_count: 1,
                 group_names: "test-group",
               })
      end
    end

    context "with multiple groups" do
      let(:group_a) { FactoryBot.create(:dependency_group, name: "group-a") }
      let(:group_b) { FactoryBot.create(:dependency_group, name: "group-b") }
      let(:multi_group_config) { FactoryBot.create(:update_config, dependency_groups: [group_a, group_b]) }
      let(:instrumented_job) do
        FactoryBot.create(:update_job,
                          update_config: multi_group_config,
                          trigger_type: :install)
      end

      it "includes group_names for small group counts" do
        instrumented_job.increment_metric("foos")

        expect(MetricsClient).to have_received(:count).
          with("foos", 1,
               tags: {
                 trigger: "install",
                 package_manager: "bundler",
                 update_type: "version",
                 runner_type: runner_type,
                 cooldown: {},
                 multi_ecosystem_update: false,
                 grouped_update: true,
                 group_count: 2,
                 group_names: "group-a,group-b",
               })
      end
    end
  end

  describe "#accessible_github_repo_ids" do
    context "when repository_access is allowed" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let!(:repository_access) do
        FactoryBot.create(:repository_access, account_id: account.id)
      end

      let(:update_job) do
        repo = FactoryBot.create(
          :repo,
          account_id: account.id,
        )
        config = FactoryBot.create(
          :update_config,
          repo: repo,
          package_manager: "go_modules"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      let(:repo_ids) { update_job.accessible_github_repo_ids }

      it "includes only the current repo id and the selected repo ids" do
        expect(repo_ids).to contain_exactly(
          update_job.update_config.repo.github_id, repository_access.github_id,
        )
      end
    end

    context "when repository_access includes the target repo" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let!(:repository_access) do
        FactoryBot.create(:repository_access, account_id: account.id)
      end

      let(:repo) do
        FactoryBot.create(
          :repo,
          account_id: account.id,
          github_id: repository_access.github_id
        )
      end

      let(:update_job) do
        config = FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "go_modules"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      let(:repo_ids) { update_job.accessible_github_repo_ids }

      it "includes only the current repo id" do
        expect(repo_ids).to contain_exactly(repo.github_id)
      end
    end

    context "when repository_access is not allowed" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let!(:repository_access) do
        FactoryBot.create(:repository_access, account_id: account.id)
      end

      let(:repo) do
        FactoryBot.create(
          :repo,
          account_id: account.id,
          github_id: repository_access.github_id
        )
      end

      let(:update_job) do
        config = FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "bundler"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      let(:repo_ids) { update_job.accessible_github_repo_ids }

      it "does not include additional repo ids" do
        expect(repo_ids).to contain_exactly(repo.github_id)
      end
    end

    context "when the access level is not set" do
      let(:repo) do
        account = FactoryBot.create(
          :account,
          github_login: "takayama"
        )

        FactoryBot.create(:repo, account_id: account.id)
      end

      let(:update_job) do
        config = FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "go_modules"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      let(:repo_ids) { update_job.accessible_github_repo_ids }

      it "includes only the current repo id" do
        expect(repo_ids).to eq([repo.github_id])
      end
    end
  end

  describe "#timing_metric" do
    let(:instrumented_job) do
      config = FactoryBot.create(:update_config,
                                 package_manager: "bundler")

      FactoryBot.create(:update_job,
                        update_config: config,
                        trigger_type: :install)
    end
    let(:runner_type) { "actions" }
    let(:cooldown) { [] }

    before do
      allow(MetricsClient).to receive(:timing)
    end

    it "times the given metric with default tags" do
      instrumented_job.timing_metric("foos", 100)

      expect(MetricsClient).to have_received(:timing).
        with("foos",
             100,
             tags: {
               trigger: "install",
               package_manager: "bundler",
               update_type: "version",
               runner_type: runner_type,
               cooldown: {},
               multi_ecosystem_update: multi_ecosystem_metric,
               grouped_update: false,
               group_count: 0,
             })
    end

    it "appends any additional tags to defaults" do
      instrumented_job.timing_metric("foos", 100, tags: { bar: "baz" })

      expect(MetricsClient).to have_received(:timing).
        with("foos",
             100,
             tags: {
               trigger: "install",
               package_manager: "bundler",
               update_type: "version",
               runner_type: runner_type,
               cooldown: {},
               bar: "baz",
               multi_ecosystem_update: multi_ecosystem_metric,
               grouped_update: false,
               group_count: 0,
             })
    end

    it "default tags may be overridden" do
      instrumented_job.timing_metric("foos", 100, tags: { package_manager: "unknown" })

      expect(MetricsClient).to have_received(:timing).
        with("foos",
             100,
             tags: {
               trigger: "install",
               package_manager: "unknown",
               update_type: "version",
               runner_type: runner_type,
               cooldown: {},
               multi_ecosystem_update: multi_ecosystem_metric,
               grouped_update: false,
               group_count: 0,
             })
    end

    context "with a dry run job" do
      let(:instrumented_job) do
        FactoryBot.create(:update_job,
                          trigger_type: :install,
                          dry_run: true)
      end

      it "does not report the metric" do
        instrumented_job.timing_metric("foos", 100)

        expect(MetricsClient).not_to have_received(:timing).with("foos", tags: anything)
      end
    end
  end

  describe "#retry!" do
    let(:job) do
      config = FactoryBot.create(:update_config,
                                 package_manager: "bundler")

      FactoryBot.create(:update_job, :processed_with_errors,
                        update_config: config)
    end
    let!(:job_error) do
      FactoryBot.create(:update_job_error, update_job: job)
    end

    let!(:job_warning) do
      FactoryBot.create(:update_job_warning, update_job: job)
    end

    let!(:other_job_error) do
      FactoryBot.create(:update_job_error)
    end

    it "deletes the existing update job errors and warnings" do
      expect do
        job.retry!
      end.to change(UpdateJobError, :count).from(2).to(1).
        and change(UpdateJobWarning, :count).from(1).to(0)

      expect(job.reload.update_job_errors).to be_empty
      expect(job.reload.update_job_warnings).to be_empty
    end

    it "enqueues a retry update job" do
      expect do
        job.retry!
      end.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with(job)
    end

    it "enqueues a retry update job with a wait" do
      freeze_time do
        wait_until = Time.at(100.seconds.from_now).in_time_zone
        wait = wait_until - Time.now.in_time_zone
        expect { job.retry!(wait: wait) }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
          at(wait_until).
          with(job)
      end
    end

    it "increments metrics" do
      allow(MetricsClient).to receive(:count)

      job.retry!

      expect(MetricsClient).to have_received(:count).with("update_job.retry", 1, anything)
    end

    it "clears the base commit SHA" do
      job.update!(base_commit_sha: "unknown")

      expect { job.retry! }.to change(job, :base_commit_sha).to(nil)
    end

    context "when the job has been run on GitHub Actions" do
      let(:job) do
        config = FactoryBot.create(:update_config, package_manager: "bundler")
        FactoryBot.create(:update_job, :processed_with_errors, :on_gh_actions, update_config: config)
      end

      it "removes the existing actions_external_id" do
        expect { job.retry! }.to change(job, :actions_external_id).to(nil)
      end

      it "removes the existing actions_workflow_run_id" do
        expect { job.retry! }.to change(job, :actions_workflow_run_id).to(nil)
      end
    end
  end

  describe "#completed?" do
    subject(:completed?) { job.completed? }

    described_class::TERMINAL_UPDATE_JOB_STATES.each do |state|
      it "#{state} state is complete" do
        job = FactoryBot.create(:update_job, state)
        expect(job.completed?).to eq(true)
      end
    end
  end

  describe "#job_metric_error_category" do
    subject(:job_metric_error_category) { job.job_metric_error_category }

    let!(:job) do
      FactoryBot.create(:update_job, :processed_with_errors)
    end

    it { is_expected.to eq("unexpected_job_state") }

    context "with a dependency_file_not_found" do
      before do
        job.update_job_errors.
          create!(error_type: "dependency_file_not_found")
      end

      it { is_expected.to eq("user_error") }
    end

    context "with a missing_environment_variable" do
      before do
        job.update_job_errors.
          create!(error_type: "missing_environment_variable")
      end

      it { is_expected.to eq("expected_error") }
    end

    context "with an unknown_error" do
      before do
        job.update_job_errors.
          create!(error_type: "unknown_error")
      end

      it { is_expected.to eq("unexpected_error") }
    end

    context "with an unrecognised error" do
      before do
        job.update_job_errors.
          create!(error_type: "pull_request_exists_error")
      end

      it { is_expected.to eq("unrecognized_error") }
    end

    context "with a processed job" do
      let(:job) do
        FactoryBot.create(:update_job, :processed)
      end

      it { is_expected.to eq("unexpected_job_state") }
    end
  end

  describe "#error_category" do
    subject(:error_category) { job.error_category(error_type: error_type) }

    let!(:job) { FactoryBot.build(:update_job) }
    let(:error_type) { nil }

    it { is_expected.to eq("unrecognized_error") }

    context "with a dependency_file_not_found" do
      let(:error_type) { "dependency_file_not_found" }

      it { is_expected.to eq("user_error") }
    end

    context "with a missing_environment_variable" do
      let(:error_type) { "missing_environment_variable" }

      it { is_expected.to eq("expected_error") }
    end

    context "with an unknown_error" do
      let(:error_type) { "unknown_error" }

      it { is_expected.to eq("unexpected_error") }
    end

    UpdateJobError::ALLOWED_UPDATE_JOB_ERROR_TYPES.each do |error_type|
      context "supports error_type: #{error_type}" do
        let(:error_type) { error_type }
        let(:expected_errors) { %w(user_error expected_error unexpected_error) }

        it "returns one of the expected error types" do
          expect(expected_errors).to include(error_category)
        end
      end
    end

    UpdateJobError::ACTIONS_SERVICE_ERRORS.each do |error_type|
      context "supports action service error_type: #{error_type}" do
        let(:error_type) { error_type }

        it "returns unexpected_error" do
          expect(error_category).to eql("unexpected_error")
        end
      end
    end

    UpdateJobError::ACTIONS_WORKFLOW_ERRORS.each do |error_type|
      context "supports action service error_type: #{error_type}" do
        let(:error_type) { error_type }

        if error_type == "self_hosted_runner_unavailable"
          it "returns user_error" do
            expect(error_category).to eql("user_error")
          end
        else
          it "returns unexpected_error" do
            expect(error_category).to eql("unexpected_error")
          end
        end
      end
    end

    %w(
      snapshots_unavailable_graph_error
      unknown_update_graph_error
      update_graph_error
    ).each do |error_type|
      context "supports upgrade graph job error_type: #{error_type}" do
        let(:error_type) { error_type }

        it "returns unexpected_error" do
          expect(error_category).to eql("unexpected_error")
        end
      end
    end
  end

  describe "#expires_at" do
    subject(:expires_at) { update_job.expires_at }

    let!(:update_job) { FactoryBot.create(:update_job, :enqueued) }

    it { is_expected.to be_nil }

    context "when the job is processing" do
      let(:processed_at) { "2020-04-13 00:00:00 UTC" }
      let(:max_run_time) { update_job.max_run_time }

      before do
        travel_to processed_at do
          update_job.transition_to!(:processing)
        end
      end

      it { is_expected.to eq(Time.parse(processed_at).utc + max_run_time) }
    end
  end

  describe "#max_run_time" do
    subject(:max_run_time) { update_job.max_run_time }

    let!(:update_job) { FactoryBot.create(:update_job) }

    it { is_expected.to eq(165.minutes + 1800.seconds) }
  end

  describe "#relevant_security_advisories" do
    let(:update_config) { FactoryBot.create(:update_config) }

    let(:update_job) do
      FactoryBot.create(:update_job,
                        update_config: update_config,
                        security_updates_only: true,
                        dependencies: ["business"],
                        trigger_type: "push")
    end

    context "there are no advisories", :api do
      let(:empty_advisories_response) { FactoryBot.build_stubbed(:advisories_response, :empty) }

      it "is empty" do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(empty_advisories_response)

        expect(update_job.relevant_security_advisories).to be_empty
      end
    end

    context "there are github security advisories", :api do
      let(:advisories_response) { FactoryBot.build_stubbed(:advisories_response, name: "business") }

      before do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(advisories_response)
      end

      it "requests from the correct ecosystem and returns the advisory" do
        result = update_job.relevant_security_advisories

        expect_advisorydb_client_to_have_requested_advisories_with(ecosystem: :ECOSYSTEM_RUBYGEMS, name: "business")

        expect(result).to be_an(Array)
        expect(result.size).to be(1)
        expect(result.first).to be_a(GitHubSecurityAdvisory)
        expect(result.first.dependency_name).to eql("business")
        expect(result.first.patched_versions).to be_nil
        expect(result.first.affected_versions).to eql(["<= 7.1.0"])
      end

      it "increments and records the duration in the fetch_security_advisories metrics" do
        expect(MetricsClient).to receive(:count).
          with("update_job.fetch_security_advisories", 1, anything)
        expect(MetricsClient).to receive(:timing).
          with("update_job.fetch_security_advisories.time", anything, anything)

        update_job.relevant_security_advisories
      end
    end

    context "there are github security advisories, but the job is a version update rebase" do
      let!(:github_advisory) do
        FactoryBot.build_stubbed(:github_security_advisory,
                                 dependency_name: "business",
                                 patched_versions: ["~> 1.11.0"],
                                 affected_versions: ["<= 1.10.0"])
      end

      let(:update_job) do
        FactoryBot.create(:update_job,
                          update_config: update_config,
                          security_updates_only: false,
                          dependencies: ["business"],
                          trigger_type: "rebase")
      end

      it "returns no advisories" do
        expect(update_job.relevant_security_advisories).to eql([])
      end
    end
  end

  describe "#relevant_security_advisories_hash", :api do
    subject(:relevant_security_advisories_hash) do
      update_job.relevant_security_advisories_hash
    end

    let(:update_config) { FactoryBot.create(:update_config) }

    let(:update_job) do
      FactoryBot.create(:update_job,
                        update_config: update_config,
                        security_updates_only: true,
                        dependencies: ["business"],
                        trigger_type: "push")
    end

    let(:empty_advisories_response) { FactoryBot.build_stubbed(:advisories_response, :empty) }

    context "there are no advisories" do
      it "is empty" do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(empty_advisories_response)

        expect(subject).to be_empty
      end
    end

    context "there are github security advisories" do
      let(:advisories_response) { FactoryBot.build_stubbed(:advisories_response, name: "business") }

      it "requests from the correct ecosystem and returns them" do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(advisories_response)

        expect(subject).to eql(
          [{
            dependency_name: "business",
            patched_versions: [],
            unaffected_versions: [],
            affected_versions: ["<= 7.1.0"],
          }]
        )

        expect_advisorydb_client_to_have_requested_advisories_with(ecosystem: :ECOSYSTEM_RUBYGEMS, name: "business")
      end
    end

    context "there are github security advisories for maven" do
      let(:advisories_response) do
        FactoryBot.build_stubbed(:advisories_response, name: "business", ecosystem: "ECOSYSTEM_MAVEN")
      end

      before do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(advisories_response)
      end

      context "and a gradle config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "gradle") }

        it "requests from the correct ecosystem and returns them converting operators to java" do
          expect(subject).to eql(
            [{
              dependency_name: "business",
              patched_versions: [],
              unaffected_versions: [],
              affected_versions: ["(,14.0.0-M1]"],
            }]
          )

          expect_advisorydb_client_to_have_requested_advisories_with(ecosystem: :ECOSYSTEM_MAVEN, name: "business")
        end
      end

      context "and a maven config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "maven") }

        it "requests from the correct ecosystem and returns them converting operators to java" do
          expect(subject).to eql(
            [{
              dependency_name: "business",
              patched_versions: [],
              unaffected_versions: [],
              affected_versions: ["(,14.0.0-M1]"],
            }]
          )

          expect_advisorydb_client_to_have_requested_advisories_with(ecosystem: :ECOSYSTEM_MAVEN, name: "business")
        end
      end

      context "and a non java config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "bundler") }

        it "requests from the correct ecosystem" do
          allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
            and_return(empty_advisories_response)

          expect(subject).to be_empty

          expect_advisorydb_client_to_have_requested_advisories_with(ecosystem: :ECOSYSTEM_RUBYGEMS)
        end
      end
    end

    context "there are github security advisories for pip" do
      let(:advisories_response) do
        FactoryBot.build_stubbed(:advisories_response, name: "numpy", ecosystem: "ECOSYSTEM_PIP")
      end

      let(:update_job) do
        FactoryBot.create(:update_job,
                          update_config: update_config,
                          security_updates_only: true,
                          dependencies: ["numpy"], # Match the advisory
                          trigger_type: "push")
      end

      before do
        allow(Dependabot::Application.advisorydb_client).to receive(:request_advisories).
          and_return(advisories_response)
      end

      context "and a conda config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "conda") }

        it "requests from the correct ecosystem and returns them" do
          expect(subject).to eql(
            [{
              dependency_name: "numpy",
              patched_versions: [],
              unaffected_versions: [],
              affected_versions: ["<= 1.5.0"],
            }]
          )

          # Should request from PIP ecosystem, not CONDA
          expect_advisorydb_client_to_have_requested_advisories_with(
            ecosystem: :ECOSYSTEM_PIP,
            name: "numpy"
          )
        end
      end

      context "and a pip config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "pip") }

        it "requests from the correct ecosystem and returns them" do
          expect(subject).to eql(
            [{
              dependency_name: "numpy",
              patched_versions: [],
              unaffected_versions: [],
              affected_versions: ["<= 1.5.0"],
            }]
          )

          expect_advisorydb_client_to_have_requested_advisories_with(
            ecosystem: :ECOSYSTEM_PIP,
            name: "numpy"
          )
        end
      end

      context "and a uv config" do
        let(:update_config) { FactoryBot.create(:update_config, package_manager: "uv") }

        it "requests from the correct ecosystem and returns them" do
          expect(subject).to eql(
            [{
              dependency_name: "numpy",
              patched_versions: [],
              unaffected_versions: [],
              affected_versions: ["<= 1.5.0"],
            }]
          )

          # Should request from PIP ecosystem, not UV
          expect_advisorydb_client_to_have_requested_advisories_with(
            ecosystem: :ECOSYSTEM_PIP,
            name: "numpy"
          )
        end
      end
    end
  end

  describe "#experiments" do
    subject(:experiments) { update_job.experiments }

    let(:update_config) { FactoryBot.create(:update_config) }
    let!(:update_job) { FactoryBot.create(:update_job, update_config: update_config) }

    context "when `timeout_per_operation` is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:timeout_per_operation)
      end

      specify { expect(update_job.experiments).to include({ timeout_per_operation_seconds: 600 }) }
    end

    context "when 'proxy_cached' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:proxy_cached)
      end

      specify { expect(update_job.experiments).to include({ proxy_cached: true }) }
    end

    context "when 'threaded_metadata_updates' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:threaded_metadata_updates)
      end

      specify { expect(update_job.experiments).to include({ threaded_metadata: true }) }
    end

    context "when 'enable_record_ecosystem_meta' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_record_ecosystem_meta)
      end

      specify { expect(update_job.experiments).to include({ enable_record_ecosystem_meta: true }) }
    end

    context "when 'enable_corepack_for_npm_and_yarn' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_corepack_for_npm_and_yarn)
      end

      specify { expect(update_job.experiments).to include({ enable_corepack_for_npm_and_yarn: true }) }
    end

    context "when 'enable_private_registry_for_corepack' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_private_registry_for_corepack)
      end

      specify { expect(update_job.experiments).to include({ enable_private_registry_for_corepack: true }) }
    end

    context "when 'enable_shared_helpers_command_timeout' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_shared_helpers_command_timeout)
      end

      specify { expect(update_job.experiments).to include({ enable_shared_helpers_command_timeout: true }) }
    end

    context "when 'enable_beta_ecosystems' is disabled in the update config" do
      before do
        update_job.update_config.update!({ enable_beta_ecosystems: false })
      end

      specify { expect(update_job.experiments).not_to include(:enable_beta_ecosystems) }
    end

    context "when 'enable_beta_ecosystems' is enabled in the update config" do
      before do
        update_job.update_config.update!({ enable_beta_ecosystems: true })
      end

      specify { expect(update_job.experiments).to include({ enable_beta_ecosystems: true }) }
    end

    context "when 'avoid_duplicate_updates_package_json' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:avoid_duplicate_updates_package_json)
      end

      specify { expect(update_job.experiments).to include({ avoid_duplicate_updates_package_json: true }) }
    end

    context "when 'allow_refresh_for_existing_pr_dependencies' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:allow_refresh_for_existing_pr_dependencies)
      end

      specify { expect(update_job.experiments).to include({ allow_refresh_for_existing_pr_dependencies: true }) }
    end

    context "when 'allow_refresh_group_with_all_dependencies' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:allow_refresh_group_with_all_dependencies)
      end

      specify { expect(update_job.experiments).to include({ allow_refresh_group_with_all_dependencies: true }) }
    end

    context "when 'enable_enhanced_error_details_for_updater' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_enhanced_error_details_for_updater)
      end

      specify { expect(update_job.experiments).to include({ enable_enhanced_error_details_for_updater: true }) }
    end

    context "when 'enhanced_grouped_security_error_reporting' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enhanced_grouped_security_error_reporting)
      end

      specify { expect(update_job.experiments).to include({ enhanced_grouped_security_error_reporting: true }) }
    end

    context "when 'enable_exclude_paths_subdirectory_manifest_files' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:enable_exclude_paths_subdirectory_manifest_files)
      end

      specify { expect(update_job.experiments).to include({ enable_exclude_paths_subdirectory_manifest_files: true }) }
    end

    context "when 'group_membership_enforcement' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:group_membership_enforcement)
      end

      specify { expect(update_job.experiments).to include({ group_membership_enforcement: true }) }
    end

    context "when 'deprecate_close_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:deprecate_close_command)
      end

      specify { expect(update_job.experiments).to include({ deprecate_close_command: true }) }
    end

    context "when 'deprecate_reopen_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:deprecate_reopen_command)
      end

      specify { expect(update_job.experiments).to include({ deprecate_reopen_command: true }) }
    end

    context "when 'deprecate_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:deprecate_merge_command)
      end

      specify { expect(update_job.experiments).to include({ deprecate_merge_command: true }) }
    end

    context "when 'deprecate_cancel_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:deprecate_cancel_merge_command)
      end

      specify { expect(update_job.experiments).to include({ deprecate_cancel_merge_command: true }) }
    end

    context "when 'deprecate_squash_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:deprecate_squash_merge_command)
      end

      specify { expect(update_job.experiments).to include({ deprecate_squash_merge_command: true }) }
    end

    context "when 'disable_close_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:disable_close_command)
      end

      specify { expect(update_job.experiments).to include({ disable_close_command: true }) }
    end

    context "when 'disable_reopen_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:disable_reopen_command)
      end

      specify { expect(update_job.experiments).to include({ disable_reopen_command: true }) }
    end

    context "when 'disable_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:disable_merge_command)
      end

      specify { expect(update_job.experiments).to include({ disable_merge_command: true }) }
    end

    context "when 'disable_cancel_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:disable_cancel_merge_command)
      end

      specify { expect(update_job.experiments).to include({ disable_cancel_merge_command: true }) }
    end

    context "when 'disable_squash_merge_command' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:disable_squash_merge_command)
      end

      specify { expect(update_job.experiments).to include({ disable_squash_merge_command: true }) }
    end

    context "when 'docker_pin_digests' is enabled on the repo" do
      before do
        update_job.repo.enable_feature(:docker_pin_digests)
      end

      specify { expect(update_job.experiments).to include({ docker_pin_digests: true }) }
    end

    context "with go_modules" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let(:private_repo) { false }

      let(:update_job) do
        repo = FactoryBot.create(
          :repo,
          account_id: account.id,
          private: private_repo
        )
        config = FactoryBot.create(
          :update_config,
          repo: repo,
          package_manager: "go_modules"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      context "with a public repo" do
        specify { expect(update_job.experiments).to include({ goprivate: "" }) }
      end

      context "with private registries" do
        before do
          registry = FactoryBot.create(
            :registry, :git,
            source: update_job.repo
          )
          update_job.update_config.update_config_registries.create!(registry_name: registry.name)
        end

        specify { expect(update_job.experiments).to include({ goprivate: "*" }) }
      end

      context "with a private repo", :cloud, :enterprise do
        let(:private_repo) { true }

        specify { expect(update_job.experiments).to include({ goprivate: "github.com/kyoto/*" }) }
      end

      context "with a private repo", :proxima do
        let(:private_repo) { true }

        specify { expect(update_job.experiments).to include({ goprivate: "staffship-01.ghe.com/kyoto/*" }) }
      end

      context "with private registries and a private repo" do
        let(:private_repo) { true }

        before do
          registry = FactoryBot.create(
            :registry, :git,
            source: update_job.repo
          )
          update_job.update_config.update_config_registries.create!(registry_name: registry.name)
        end

        specify { expect(update_job.experiments).to include({ goprivate: "*" }) }
      end
    end
  end

  describe "#reportable_experiments" do
    subject(:reportable_experiments) { update_job.reportable_experiments }

    let!(:update_job) { FactoryBot.create(:update_job) }

    it "doesn't include the default experiments" do
      expect(reportable_experiments).to eq({})
    end

    context "with an ignored experiment" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let(:update_job) do
        repo = FactoryBot.create(
          :repo,
          account_id: account.id
        )
        config = FactoryBot.create(
          :update_config,
          repo: repo,
          package_manager: "go_modules"
        )

        FactoryBot.create(
          :update_job,
          update_config: config,
          trigger_type: :install,
        )
      end

      it "doesn't include the experiment" do
        expect(reportable_experiments).to eq({})
      end
    end

    context "with an allowed experiment" do
      before do
        update_job.repo.enable_feature(:timeout_per_operation)
      end

      it "includes the experiment" do
        expect(reportable_experiments).to eq({ timeout_per_operation_seconds: 600 })
      end
    end
  end

  describe "#staging_enabled_on_repo?" do
    subject(:staging_enabled_on_repo?) { update_job.staging_enabled_on_repo? }

    let!(:update_job) { FactoryBot.create(:update_job) }

    it do
      expect(subject).to eq(false)
    end

    context "with job_sqs_stage" do
      before { Flipper.enable_actor(:job_sqs_stage, update_job.update_config.repo) }

      it do
        expect(subject).to eq(true)
      end
    end
  end

  describe "#ignore_conditions_hash" do
    subject(:ignore_conditions_hash) { update_job.ignore_conditions_hash }

    let!(:update_job) { FactoryBot.create(:update_job) }
    # 3 specifies the number of fractional digits for seconds
    let(:timestamp) do
      Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
    end

    it do
      expect(ignore_conditions_hash).to eq([])
    end

    context "with ignore conditions" do
      before do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_job.update_config,
          updated_at: timestamp,
        )
        FactoryBot.create(
          :ignore_condition,
          version_requirement: ">= 0",
          updated_at: timestamp,
        )
      end

      it "returns all associated ones" do
        expect(ignore_conditions_hash).
          to eq([{
                  dependency_name: "business",
                  version_requirement: ">= 2.0, < 3",
                  update_types: nil,
                  source: "@dependabot ignore command",
                  updated_at: timestamp,
                }])
      end
    end
  end

  describe "validations" do
    it { is_expected.to be_valid }

    it "allows valid metrics_metadata as a hash" do
      update_job.metrics_metadata = { package_manager: { bundler: "2" } }
      expect(update_job).to be_valid
    end

    it "allows valid metrics_metadata as a JSON string" do
      update_job.metrics_metadata = { package_manager: { bundler: "2" } }.to_json
      expect(update_job).to be_valid
    end

    describe "#metrics_metadata" do
      it "validates the object is valid JSON" do
        update_job.metrics_metadata = "invalid"
        expect(update_job).not_to be_valid
        expect(update_job.errors[:metrics_metadata]).to include("must be valid JSON")
      end

      it "validates validates the object can be coerced to a Hash" do
        update_job.metrics_metadata = "[\"invalid\"]"
        expect(update_job).not_to be_valid
        expect(update_job.errors[:metrics_metadata]).to include("must be a JSON object")
      end
    end

    describe "#triggered_by_ghsa_id" do
      it "validates the id is correctly formatted" do
        update_job.trigger_type = :scan
        update_job.triggered_by_ghsa_id = "GHSA-1111-1111-1111"
        expect(update_job).not_to be_valid
      end

      UpdateJob::SECURITY_TRIGGER_TYPES.each do |trigger|
        it "is valid with a #{trigger} trigger" do
          update_job.trigger_type = trigger
          update_job.triggered_by_ghsa_id = FactoryBot.generate(:ghsa_id)
          expect(update_job).to be_valid
        end
      end

      it "is valid with an unknown trigger" do
        update_job.trigger_type = :unknown
        update_job.triggered_by_ghsa_id = FactoryBot.generate(:ghsa_id)
        expect(update_job).to be_valid
      end

      [
        UpdateJob::SCHEDULED_TRIGGER_TYPES,
        UpdateJob::REBASE_TRIGGER_TYPES,
      ].flatten.each do |trigger|
        it "is invalid with a #{trigger} trigger" do
          update_job.trigger_type = trigger
          update_job.triggered_by_ghsa_id = FactoryBot.generate(:ghsa_id)
          expect(update_job).not_to be_valid
        end
      end
    end
  end

  describe "#dependency_groups" do
    context "when the job is a version update" do
      it "returns non-security-update dependency groups" do
        version_update_group = build_stubbed(:dependency_group)
        security_update_group = build_stubbed(:dependency_group, :applies_to_security)
        dependency_groups = [version_update_group, security_update_group]
        grouped_update_config = build(:update_config, dependency_groups: dependency_groups)
        update_job = build_stubbed(:update_job, :version_update, update_config: grouped_update_config)

        expect(update_job.dependency_groups).to eq([version_update_group])
      end

      it "returns an empty collection when no groups have been defined" do
        update_job = build_stubbed(:update_job, :version_update)

        expect(update_job.dependency_groups).to be_empty
      end
    end

    context "when the job is a security update" do
      it "returns security-update dependency groups" do
        version_update_group = build_stubbed(:dependency_group)
        security_update_group = build_stubbed(:dependency_group, :applies_to_security)
        dependency_groups = [version_update_group, security_update_group]
        grouped_update_config = build(:update_config, dependency_groups: dependency_groups)
        update_job = build_stubbed(:update_job, :security_update, update_config: grouped_update_config)

        expect(update_job.dependency_groups).to eq([security_update_group])
      end

      it "returns an empty collection when no groups have been defined" do
        update_job = build_stubbed(:update_job, :security_update)

        expect(update_job.dependency_groups).to be_empty
      end
    end
  end

  describe "#grouping_requested?" do
    context "when the job is a version update" do
      it "returns true when (version-update) dependency groups are defined" do
        dependency_group = build_stubbed(:dependency_group)
        grouped_update_config = build(:update_config, dependency_groups: [dependency_group])
        update_job = build_stubbed(:update_job, :version_update, update_config: grouped_update_config)

        expect(update_job).to be_grouping_requested
      end

      it "returns false when no dependency groups are defined" do
        update_config = build_stubbed(:update_config)
        update_job = build_stubbed(:update_job, :version_update, update_config: update_config)

        expect(update_config.dependency_groups).to be_empty
        expect(update_job).not_to be_grouping_requested
      end

      it "returns false when only security-update dependency groups are defined" do
        dependency_group = build_stubbed(:dependency_group, :applies_to_security)
        grouped_update_config = build(:update_config, dependency_groups: [dependency_group])
        update_job = build_stubbed(:update_job, :version_update, update_config: grouped_update_config)

        expect(update_job).not_to be_grouping_requested
      end
    end

    context "when the job is a security update" do
      it "returns true when (security-update) dependency groups are defined" do
        dependency_group = build_stubbed(:dependency_group, :applies_to_security)
        grouped_update_config = build(:update_config, dependency_groups: [dependency_group])
        update_job = build_stubbed(:update_job, :security_update, update_config: grouped_update_config)

        expect(update_job).to be_grouping_requested
      end

      it "returns true when there are no groups but the repository has grouping enabled" do
        repo = create(:repo)
        update_config = create(:update_config, repo: repo)
        dependencies = %w(business)
        update_job = create(:update_job, :security_update, update_config: update_config,
                                                           dependencies: dependencies)

        stub_monolith_settings(security_updates_grouping_enabled: true)

        expect(update_job).to be_grouping_requested
      end

      it "returns false when there are no groups and the repository has grouping disabled" do
        update_config = build_stubbed(:update_config)
        dependencies = %w(business rubocop)
        update_job = build_stubbed(:update_job, :version_update, update_config: update_config,
                                                                 dependencies: dependencies)

        stub_monolith_settings(security_updates_grouping_enabled: false)

        expect(update_config.dependency_groups).to be_empty
        expect(update_job.dependencies.count).to eq(2)
        expect(update_job).not_to be_grouping_requested
      end
    end
  end

  describe "#fallback_dependency_group" do
    it "returns a FallbackDependencyGroup" do
      update_job = build_stubbed(:update_job)

      expect(update_job.fallback_dependency_group).to be_a(FallbackDependencyGroup)
    end

    it "is named after the package manager" do
      package_manager = "hex"
      update_config = build_stubbed(:update_config, package_manager: package_manager)
      update_job = build_stubbed(:update_job, update_config: update_config)

      fallback_group = update_job.fallback_dependency_group

      expect(fallback_group.name).to eq(package_manager)
    end

    it "groups all dependencies" do
      update_job = build_stubbed(:update_job)

      fallback_group = update_job.fallback_dependency_group

      expect(fallback_group.rules).to eq({ "patterns" => ["*"] })
    end
  end

  describe "#telemetry_attributes" do
    context "when job has grouping requested" do
      let(:dependency_group) { build_stubbed(:dependency_group, name: "test-group", applies_to: "version-updates") }
      let(:grouped_update_config) { build(:update_config, dependency_groups: [dependency_group]) }
      let(:update_job) { build_stubbed(:update_job, :version_update, update_config: grouped_update_config) }

      it "includes group-specific telemetry attributes" do
        allow(update_job).to receive(:current_dependency_group).and_return(dependency_group)

        attributes = update_job.telemetry_attributes

        expect(attributes).to include(
          "gh.dependabot_api.update_job.grouping_requested" => true,
          "gh.dependabot_api.update_job.dependency_groups_count" => 1,
          "gh.dependabot_api.update_job.current_group_name" => "test-group",
          "gh.dependabot_api.update_job.current_group_applies_to" => "version-updates"
        )
      end
    end

    context "when job is multi-ecosystem update" do
      let(:update_config) { build_stubbed(:update_config, multi_ecosystem_config_id: 123) }
      let(:update_job) { build_stubbed(:update_job, update_config:, enqueue_scheduled_update_id: "456") }

      it "includes multi-ecosystem telemetry attributes" do
        attributes = update_job.telemetry_attributes

        expect(attributes).to include(
          "gh.dependabot_api.update_job.multi_ecosystem_update" => true,
          "gh.dependabot_api.update_job.multi_ecosystem_config_id" => 123,
          "gh.dependabot_api.update_job.enqueue_scheduled_update_id" => "456"
        )
      end
    end

    context "when job is not grouped and not multi-ecosystem" do
      let(:update_job) { build_stubbed(:update_job) }

      it "does not include group-specific attributes" do
        attributes = update_job.telemetry_attributes

        expect(attributes).not_to have_key("gh.dependabot_api.update_job.grouping_requested")
        expect(attributes).not_to have_key("gh.dependabot_api.update_job.multi_ecosystem_update")
      end
    end
  end

  describe "logging" do
    let(:update_job) { FactoryBot.create(:update_job) }

    before { allow(Dependabot::Logger).to receive(:info) }

    it "logs when the job state is transitioned" do
      update_job.transition_to(:enqueued)

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "UpdateJob state changed.",
               "code.namespace": "UpdateJobStateMachine",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
               "gh.dependabot_api.update_job.created_at": update_job.created_at,
               "gh.dependabot_api.update_job.trigger_type": update_job.trigger_type,
               "gh.dependabot_api.update_job.from_state": "pending",
               "gh.dependabot_api.update_job.to_state": "enqueued",
             ))
    end

    it "logs when the job state is force-transitioned" do
      update_job.transition_to!(:enqueued)

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "UpdateJob state changed.",
               "code.namespace": "UpdateJobStateMachine",
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
               "gh.dependabot_api.update_job.created_at": update_job.created_at,
               "gh.dependabot_api.update_job.trigger_type": update_job.trigger_type,
               "gh.dependabot_api.update_job.from_state": "pending",
               "gh.dependabot_api.update_job.to_state": "enqueued",
             ))
    end
  end

  describe "multi ecosystem relations" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, :active, multi_ecosystem_config:) }
    let(:sibling_update_config) { create(:update_config, :active, multi_ecosystem_config:) }
    let(:unrelated_update_config) { create(:update_config, :active) }

    let(:enqueue_scheduled_update_id) { SecureRandom.uuid }
    let(:update_job) { create(:update_job, update_config:) }
    let(:multi_ecosystem_metric) { true }

    describe "#multi_ecosystem_siblings" do
      it "returns all sibling jobs including itself" do
        sibling_update_job = create(:update_job, update_config: sibling_update_config)
        expect(update_job.multi_ecosystem_siblings).to contain_exactly(update_job, sibling_update_job)
      end

      it "does not include unrelated jobs" do
        unrelated_update_job = create(:update_job, update_config: unrelated_update_config)
        expect(update_job.multi_ecosystem_siblings).not_to include(unrelated_update_job)
      end

      it "returns none when multi_ecosystem_config_id is nil" do
        update_job.update_config.update!(multi_ecosystem_config_id: nil)
        expect(update_job.multi_ecosystem_siblings).to be_empty
      end
    end

    describe "#multi_ecosystem_siblings_enqueued_together" do
      before do
        update_job.update!(enqueue_scheduled_update_id:)
      end

      it "returns sibling jobs enqueued together including itself" do
        sibling_enqueued_job = create(:update_job,
                                      update_config: sibling_update_config,
                                      enqueue_scheduled_update_id: enqueue_scheduled_update_id)
        expect(update_job.multi_ecosystem_siblings_enqueued_together).to contain_exactly(update_job,
                                                                                         sibling_enqueued_job)
      end

      it "does not include unrelated enqueued jobs" do
        unrelated_enqueued_job = create(:update_job,
                                        update_config: unrelated_update_config,
                                        enqueue_scheduled_update_id: enqueue_scheduled_update_id)
        expect(update_job.multi_ecosystem_siblings_enqueued_together).not_to include(unrelated_enqueued_job)
      end

      it "returns none when enqueue_scheduled_update_id is nil" do
        update_job.update!(enqueue_scheduled_update_id: nil)
        expect(update_job.multi_ecosystem_siblings_enqueued_together).to be_empty
      end

      it "returns none when multi_ecosystem_config_id is nil" do
        update_job.update_config.update!(multi_ecosystem_config_id: nil)
        expect(update_job.multi_ecosystem_siblings_enqueued_together).to be_empty
      end
    end

    describe "scope :enqueued_together" do
      let(:enqueued_job) { create(:update_job, enqueue_scheduled_update_id: enqueue_scheduled_update_id) }
      let(:enqueued_job_sibling) { create(:update_job, enqueue_scheduled_update_id: enqueue_scheduled_update_id) }

      before { create(:update_job) }

      it "returns jobs enqueued together with the given enqueue_scheduled_update_id" do
        expect(described_class.enqueued_together(enqueue_scheduled_update_id)).to contain_exactly(enqueued_job,
                                                                                                  enqueued_job_sibling)
      end
    end

    describe "#multi_ecosystem_config_id" do
      it "is delegated to update_config" do
        expect(update_job.multi_ecosystem_config_id).to eq(multi_ecosystem_config.id)
      end
    end
  end

  describe "#multi_ecosystem_update?" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, multi_ecosystem_config: multi_ecosystem_config) }

    context "when both multi_ecosystem_config_id and enqueue_scheduled_update_id are present" do
      let(:update_job) do
        create(:update_job,
               update_config: update_config,
               enqueue_scheduled_update_id: SecureRandom.uuid)
      end

      it "returns true" do
        expect(update_job.multi_ecosystem_update?).to eq(true)
      end
    end

    context "when multi_ecosystem_config_id is missing" do
      let(:update_config) { create(:update_config, multi_ecosystem_config: nil) }
      let(:update_job) do
        create(:update_job,
               update_config: update_config,
               enqueue_scheduled_update_id: SecureRandom.uuid)
      end

      it "returns false" do
        expect(update_job.multi_ecosystem_update?).to eq(false)
      end
    end

    context "when enqueue_scheduled_update_id is missing" do
      let(:update_job) do
        create(:update_job,
               update_config: update_config,
               enqueue_scheduled_update_id: nil)
      end

      it "returns false" do
        expect(update_job.multi_ecosystem_update?).to eq(false)
      end
    end
  end

  describe "#current_state" do
    it "is set to initial state on new records" do
      update_job = build(:update_job)
      expect(update_job.attributes["current_state"]).to eq(UpdateJobStateMachine.initial_state)
    end

    it "is not set to initial state on existing records" do
      update_job = create(:update_job, :enqueued)

      loaded_from_db = described_class.find(update_job.id)
      expect(loaded_from_db.attributes["current_state"]).to eq("enqueued")
    end

    it "is validated to be a known update job state machine state" do
      update_job.current_state = "nonexistent_state"
      expect(update_job).not_to be_valid
    end
  end

  describe ".in_state" do
    it "uses the current_state column" do
      # create jobs with different states recorded in transition history
      # and the current_state column
      processing_update_job = create(:update_job, :pending).tap { |job| job.update!(current_state: :processing) }
      enqueued_update_job = create(:update_job, :pending).tap { |job| job.update!(current_state: :enqueued) }

      results = described_class.in_state(:processing).to_a

      expect(results).to include(processing_update_job)
      expect(results).not_to include(enqueued_update_job)
    end
  end

  describe ".not_in_state" do
    it "uses the current_state column" do
      # create jobs with different states recorded in transition history
      # and the current_state column
      processing_update_job = create(:update_job, :pending).tap { |job| job.update!(current_state: :processing) }
      enqueued_update_job = create(:update_job, :pending).tap { |job| job.update!(current_state: :enqueued) }

      results = described_class.not_in_state(:processing).to_a

      expect(results).to include(enqueued_update_job)
      expect(results).not_to include(processing_update_job)
    end
  end

  private

  def expect_advisorydb_client_to_have_requested_advisories_with(ecosystem:, name: "business")
    expect(Dependabot::Application.advisorydb_client).to have_received(:request_advisories).
      with(packages: [hash_including(ecosystem:, name:)])
  end
end
