# frozen_string_literal: true

require "rails_helper"

EXPECTED_FILE_MODE = "100644"

RSpec.describe CombinePullRequestsAfterJobsCompletion do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.perform_later(associated_update_job_ids: associated_update_job_ids)
  end

  let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }

  let(:update_configs) do
    [
      create(:update_config, :with_multi_ecosystem_config, :active, multi_ecosystem_config:,
                                                                    package_manager: "bundler"),
      create(:update_config, :with_multi_ecosystem_config, :active, multi_ecosystem_config:,
                                                                    package_manager: "npm_and_yarn"),
    ]
  end

  let(:update_jobs) do
    [
      create(:update_job, :processed, update_config: update_configs.first),
      create(:update_job, :processed, update_config: update_configs.second),
    ]
  end

  let(:associated_update_job_ids) do
    update_jobs.map(&:id)
  end

  let(:pending_prs) do
    update_jobs.map.with_index do |job, index|
      pr = PendingPullRequest.create!(
        update_job: job,
        updated_dependency_details: [
          {
            "name" => "business.#{index}",
            "package_manager" => "bundler",
            "previous_requirements" => [
              {
                "file" => "file",
                "groups" => ["default"],
                "requirement" => "~> 1.3.0",
                "source" => nil,
              },
            ],
            "requirements" => [
              {
                "file" => "file",
                "groups" => [],
                "requirement" => "~> 1.8.0",
                "source" => nil,
              },
            ],
            "version" => "1.8.0",
          },
        ],
        sort_key: index + 1,
      )
      pr.encrypted_dependency_files_blob.attach(
        io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
        filename: pr.id,
        content_type: "application/octet-stream",
        identify: false,
      )
      pr.message_data = {
        commit_message: "Message for job with index #{index}",
        pr_title: "Title for job with index #{index}",
        pr_body: "Body for job with index #{index}",
      }

      pr
    end
  end

  let(:files) do
    [
      {
        content: "some things",
        name: "Gemfile",
        directory: "/",
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
        mode: EXPECTED_FILE_MODE,
      },
      {
        content: "more things",
        name: "Gemfile.lock",
        directory: "/",
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
        mode: EXPECTED_FILE_MODE,
      },
    ]
  end

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  def combined_message_data_from_jobs(attribute)
    update_jobs.flat_map do |job|
      job.pending_pull_requests.flat_map { |pr| pr.message_data[attribute] }
    end
  end

  before do
    allow(PendingPullRequest).to receive(:where).and_return(pending_prs)
    allow(MetricsClient).to receive(:increment)
  end

  describe "when all associated update jobs are complete" do
    let(:update_job) { update_jobs.last }

    it "sets the combined PR title to include the multi-ecosystem name" do
      allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later) do |args|
        combined_pending_pr = args[:pending_pr]
        expect(combined_pending_pr.message_data["pr_title"]).to include(multi_ecosystem_config.name)
      end

      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
    end

    it "uses TitleBuilder for the combined PR title" do
      expect(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later) do |args|
        combined_pending_pr = args[:pending_pr]
        expect(combined_pending_pr.message_data["pr_title"]).to eq(
          "Bump the \"#{multi_ecosystem_config.name}\" group with " \
          "#{pending_prs.size} updates across multiple ecosystems"
        )
      end

      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
    end

    context "when update config has commit message prefix" do
      before do
        update_configs.first.update!(commit_message_prefix: "[ci]")
      end

      it "applies the prefix to the combined PR title" do
        expect(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later) do |args|
          combined_pending_pr = args[:pending_pr]
          expect(combined_pending_pr.message_data["pr_title"]).to eq(
            "[ci]: Bump the \"#{multi_ecosystem_config.name}\" group with " \
            "#{pending_prs.size} updates across multiple ecosystems"
          )
        end

        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
      end
    end

    context "when update config has commit message prefix with trailing space" do
      before do
        update_configs.first.update!(commit_message_prefix: "[ci] ")
      end

      it "preserves the trailing space without adding a colon" do
        expect(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later) do |args|
          combined_pending_pr = args[:pending_pr]
          expect(combined_pending_pr.message_data["pr_title"]).to eq(
            "[ci] Bump the \"#{multi_ecosystem_config.name}\" group with " \
            "#{pending_prs.size} updates across multiple ecosystems"
          )
        end

        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
      end
    end
  end

  describe "metrics recording" do
    before do
      allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
      allow(MetricsClient).to receive(:increment).with(anything, any_args)
    end

    it "records metrics for each ecosystem and the combined ecosystems" do # rubocop:disable RSpec/ExampleLength
      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
      expect(MetricsClient).to have_received(:increment).with(
        "multi_ecosystem.combine_pull_request.start",
        { tags: { grouped_update: true, group_count: 1, group_names: "my_multi_ecosystem_config" } }
      )
      expect(MetricsClient).to have_received(:increment).with(
        "multi_ecosystem.combine_pull_request.success",
        { tags: { grouped_update: true, group_count: 1, group_names: "my_multi_ecosystem_config" } }
      )
      expect(MetricsClient).to have_received(:increment).with(
        "multi_ecosystem.ecosystem",
        { tags: { package_manager: "bundler", grouped_update: true, group_count: 1,
                  group_names: "my_multi_ecosystem_config", } }
      )
      expect(MetricsClient).to have_received(:increment).with(
        "multi_ecosystem.ecosystem",
        { tags: { package_manager: "npm_and_yarn", grouped_update: true, group_count: 1,
                  group_names: "my_multi_ecosystem_config", } }
      )
      expect(MetricsClient).to have_received(:increment).with(
        "multi_ecosystem.ecosystem.combined",
        { tags: { package_managers: %w(bundler npm_and_yarn), grouped_update: true, group_count: 1,
                  group_names: "my_multi_ecosystem_config", } }
      )
    end
  end

  context "when updating a pull request" do
    let(:existing_pr) do
      create(:pull_request, :updating, :for_a_multi_ecosystem_update, update_config: update_configs.first)
    end
    let(:linked_update_job) { update_jobs.first }
    let(:combined_pr) { PendingPullRequest.where(update_job_id: linked_update_job.id).first }

    let(:combined_pending_pr) { pending_prs.last }

    before do
      # Set up the bidirectional relationship: the transition points to the job,
      # and the job points back to the transition. For multi-ecosystem updates,
      # only the first job should have pull_request_transition_id set.
      existing_pr.last_transition.update!(update_job_id: linked_update_job.id)
      linked_update_job.update!(pull_request_transition_id: existing_pr.last_transition.id)

      allow(Dependabot::Logger).to receive(:info)
      allow(Dependabot::Logger).to receive(:warn)
      allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
    end

    it "logs info about updating existing PR" do
      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

      expect(Dependabot::Logger).to have_received(:info).with(
        hash_including(
          msg: "Found existing updating PR, updating it with the combined PR",
          existing_pr_in_updating_state_id: existing_pr.id,
          combined_pr_id: combined_pr.id,
          linked_update_job_id: linked_update_job.id,
        )
      )
    end

    it "enqueues PrioritizedJobs::CreatePullRequestOnGitHub" do
      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

      expect(PrioritizedJobs::CreatePullRequestOnGitHub).to have_received(:perform_later).with(
        pending_pr: kind_of(PendingPullRequest),
      )
    end

    it "uses the correct combined PR according to linked_update_job" do
      described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

      expect(combined_pr.update_job_id).to eq(linked_update_job.id)
    end

    context "when all jobs have pull_request_transition_id set (backwards compatibility)" do
      before do
        # Simulate pre-deployment data where ALL jobs have pull_request_transition_id set
        update_jobs.each do |job|
          job.update!(pull_request_transition_id: existing_pr.last_transition.id)
        end
      end

      it "finds the first job with transition_id and succeeds" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(PrioritizedJobs::CreatePullRequestOnGitHub).to have_received(:perform_later).with(
          pending_pr: kind_of(PendingPullRequest),
        )
      end
    end

    context "when no jobs have pull_request_transition_id set" do
      before do
        # Force existing_pr to be created first (triggers parent before block's lazy lets)
        existing_pr

        # Now clear the transition_id from all jobs to simulate edge case
        update_jobs.each do |job|
          job.reload.update!(pull_request_transition_id: nil)
        end
      end

      it "records the no_matching_update_job_error metric and does not create a PR" do
        # Verify the setup is correct
        expect(existing_pr.in_state?(:updating)).to be true
        expect(update_jobs.map { |j| j.reload.pull_request_transition_id }).to all(be_nil)

        # The job should record the error metric when no job has pull_request_transition_id
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(MetricsClient).to have_received(:increment).with(
          "multi_ecosystem.combine_pull_request.no_matching_update_job_error",
          anything
        )

        # No PR should be created since the linked update job could not be found
        expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to have_received(:perform_later)
      end
    end

    context "when multiple PRs are in updating state" do
      before do
        # create an `:updating` pull request for the same multi ecosystem update
        create(:pull_request, :updating, :for_a_multi_ecosystem_update, update_config: update_configs.second)
        allow(Dependabot::Logger).to receive(:warn)
      end

      it "logs a warning" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(Dependabot::Logger).to have_received(:warn).with(
          msg: "Multiple updating PRs found for the same update config",
          at: "CombinePullRequestsAfterJobsCompletion",
          associated_update_job_ids: associated_update_job_ids,
          associated_update_job_count: associated_update_job_ids.length,
          associated_update_config_count: multi_ecosystem_config.update_configs.count,
          multi_ecosystem_config_name: multi_ecosystem_config.name,
          multi_ecosystem_config_id: multi_ecosystem_config.id,
          existing_prs_count: 2
        )
      end
    end

    context "when all jobs are not processed" do
      let(:update_jobs) do
        [
          create(:update_job, :processed, update_config: update_configs.first),
          create(:update_job, :pending, update_config: update_configs.second),
        ]
      end

      context "when there is a deleted update_config" do
        let(:update_jobs) do
          [
            create(:update_job, :processed, update_config: update_configs.first),
            create(:update_job, :processed, update_config: update_configs.second),
          ]
        end

        it "enqueues PrioritizedJobs::CreatePullRequestOnGitHub" do
          create(:update_config, :with_multi_ecosystem_config, :deleted, multi_ecosystem_config:,
                                                                         package_manager: "cargo")

          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(PrioritizedJobs::CreatePullRequestOnGitHub).to have_received(:perform_later)
        end
      end

      it "does not enqueue PrioritizedJobs::CreatePullRequestOnGitHub" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to have_received(:perform_later)
      end

      context "when they are not all queued" do
        let(:update_jobs) do
          [
            create(:update_job, :pending, update_config: update_configs.first),
          ]
        end

        it "does not enqueue PrioritizedJobs::CreatePullRequestOnGitHub" do
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to have_received(:perform_later)
        end
      end
    end
  end

  describe "grouped update metrics" do
    before do
      allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
      allow(MetricsClient).to receive(:increment)
    end

    context "records metrics with group context for successful combination" do
      it "emits success metrics" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(MetricsClient).to have_received(:increment).with(
          "multi_ecosystem.combine_pull_request.start",
          { tags: { grouped_update: true, group_count: 1, group_names: "my_multi_ecosystem_config" } }
        )
        expect(MetricsClient).to have_received(:increment).with(
          "multi_ecosystem.combine_pull_request.success",
          { tags: { grouped_update: true, group_count: 1, group_names: "my_multi_ecosystem_config" } }
        )
      end
    end

    context "when jobs are not all complete" do
      let(:incomplete_update_jobs) do
        [
          create(:update_job, :processed, update_config: update_configs.first),
          create(:update_job, :processing, update_config: update_configs.second), # Not complete
        ]
      end
      let(:associated_update_job_ids) { incomplete_update_jobs.map(&:id) }

      it "records skipped metric with group context" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(MetricsClient).to have_received(:increment).with(
          "multi_ecosystem.combine_pull_request.skipped",
          { tags: { reason: "incomplete_jobs", grouped_update: true, group_count: 1,
                    group_names: "my_multi_ecosystem_config", } }
        )
      end
    end

    # NOTE: Additional edge case scenarios (no pending PRs, exceptions) are covered by the
    # error handling code in the job implementation and are difficult to test cleanly due to
    # complex test setup interdependencies, but the core functionality is validated above

    context "when all jobs are terminal but not all successfully processed" do
      let(:failed_update_jobs) do
        [
          create(:update_job, :processed, update_config: update_configs.first),
          create(:update_job, :processed_with_errors, update_config: update_configs.second),
        ]
      end
      let(:associated_update_job_ids) { failed_update_jobs.map(&:id) }

      # Create pending PRs for the failed jobs
      let(:failed_pending_prs) do
        failed_update_jobs.map.with_index do |job, index|
          pr = PendingPullRequest.create!(
            update_job: job,
            updated_dependency_details: [
              {
                "name" => "business.#{index}",
                "package_manager" => job.package_manager,
                "previous_requirements" => [
                  {
                    "file" => "file",
                    "groups" => ["default"],
                    "requirement" => "~> 1.3.0",
                    "source" => nil,
                  },
                ],
                "requirements" => [
                  {
                    "file" => "file",
                    "groups" => ["default"],
                    "requirement" => "~> 1.4.0",
                    "source" => nil,
                  },
                ],
                "version" => "1.4.0",
              },
            ],
            sort_key: index + 1,
          )
          pr.encrypted_dependency_files_blob.attach(
            io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
            filename: pr.id,
            content_type: "application/octet-stream",
            identify: false,
          )
          pr.message_data = {
            "commit_message" => "Bump business.#{index} from 1.3.0 to 1.4.0",
            "pr_body" => "Bumps business.#{index} from 1.3.0 to 1.4.0.",
            "pr_title" => "Bump business.#{index} from 1.3.0 to 1.4.0",
          }
          pr
        end
      end

      before do
        allow(PendingPullRequest).to receive(:where).and_return(failed_pending_prs)
        allow(CancelStalePullRequestUpdate).to receive(:perform_later)
        allow(MetricsClient).to receive(:increment)
      end

      it "records failed metric with not_all_jobs_successful reason" do
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

        expect(MetricsClient).to have_received(:increment).with(
          "multi_ecosystem.combine_pull_request.failed",
          { tags: { reason: "not_all_jobs_successful", grouped_update: true, group_count: 1,
                    group_names: "my_multi_ecosystem_config", } }
        )
      end

      it "does not enqueue CreatePullRequestOnGitHub job" do
        expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to receive(:perform_later)
        described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
      end

      context "when there are PRs in updating state" do
        let!(:updating_pr) do
          create(:pull_request, :updating, update_config: update_configs.first)
        end

        before do
          # Link the PR transition to one of our failed jobs
          updating_pr.last_transition.update!(update_job_id: failed_update_jobs.first.id)
          # Make sure the transition is marked as most recent
          updating_pr.last_transition.update!(most_recent: true)
        end

        it "schedules CancelStalePullRequestUpdate for updating PRs" do
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(CancelStalePullRequestUpdate).to have_received(:perform_later).with(
            update_job: failed_update_jobs.first
          )
        end

        it "records cancel_updating_pr metric" do
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(MetricsClient).to have_received(:increment).with(
            "multi_ecosystem.combine_pull_request.cancel_updating_pr",
            { tags: { grouped_update: true, group_count: 1, group_names: "my_multi_ecosystem_config" } }
          )
        end

        context "when the PR transition is not most recent" do
          before do
            updating_pr.last_transition.update!(most_recent: false)
          end

          it "does not schedule CancelStalePullRequestUpdate" do
            described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

            expect(CancelStalePullRequestUpdate).not_to have_received(:perform_later)
          end
        end

        context "when no matching update job is found" do
          before do
            # Set the transition to point to a non-existent job
            updating_pr.last_transition.update!(update_job_id: 99999)
          end

          it "does not schedule CancelStalePullRequestUpdate" do
            described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

            expect(CancelStalePullRequestUpdate).not_to have_received(:perform_later)
          end
        end
      end

      context "when there are no PRs in updating state" do
        it "does not schedule any CancelStalePullRequestUpdate jobs" do
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(CancelStalePullRequestUpdate).not_to have_received(:perform_later)
        end
      end
    end

    context "with various terminal job states" do
      shared_context "terminal job state setup" do |state_param|
        # Capture the parameter in a let block to avoid variable scoping issues
        let(:job_state) { state_param }

        # Override the main update_jobs let block with mixed states
        let(:update_jobs) do
          [
            create(:update_job, :processed, update_config: update_configs.first),
            create(:update_job, job_state, update_config: update_configs.second),
          ]
        end

        # The associated_update_job_ids should automatically pick up the new update_jobs,
        # but let's be explicit to ensure it works
        let(:associated_update_job_ids) do
          update_jobs.map(&:id)
        end

        # Override the main pending_prs let block for our mixed scenario
        let(:pending_prs) do
          update_jobs.map.with_index do |job, index|
            pr = PendingPullRequest.create!(
              update_job: job,
              updated_dependency_details: [
                {
                  "name" => "business.#{index}",
                  "package_manager" => job.package_manager,
                  "previous_requirements" => [
                    {
                      "file" => "file",
                      "groups" => ["default"],
                      "requirement" => "~> 1.3.0",
                      "source" => nil,
                    },
                  ],
                  "requirements" => [
                    {
                      "file" => "file",
                      "groups" => ["default"],
                      "requirement" => "~> 1.4.0",
                      "source" => nil,
                    },
                  ],
                  "version" => "1.4.0",
                },
              ],
              sort_key: index + 1,
            )
            pr.encrypted_dependency_files_blob.attach(
              io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
              filename: pr.id,
              content_type: "application/octet-stream",
              identify: false,
            )
            pr.message_data = {
              "commit_message" => "Bump business.#{index} from 1.3.0 to 1.4.0",
              "pr_body" => "Bumps business.#{index} from 1.3.0 to 1.4.0.",
              "pr_title" => "Bump business.#{index} from 1.3.0 to 1.4.0",
            }
            pr
          end
        end

        before do
          # Override the main before block mocks for our scenario
          allow(PendingPullRequest).to receive(:where).and_return(pending_prs)
          allow(CancelStalePullRequestUpdate).to receive(:perform_later)
          allow(MetricsClient).to receive(:increment)
          allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
        end
      end

      shared_examples "failed terminal state" do |job_state|
        include_context "terminal job state setup", job_state

        it "cancels updating PRs for #{job_state} state" do
          expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to receive(:perform_later)
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)

          expect(MetricsClient).to have_received(:increment).with(
            "multi_ecosystem.combine_pull_request.failed",
            { tags: { reason: "not_all_jobs_successful", grouped_update: true, group_count: 1,
                      group_names: "my_multi_ecosystem_config", } }
          )
        end
      end

      # Successful terminal states
      context "when both jobs are processed" do
        let(:update_jobs) do
          [
            create(:update_job, :processed, update_config: update_configs.first),
            create(:update_job, :processed, update_config: update_configs.second),
          ]
        end

        let(:associated_update_job_ids) do
          update_jobs.map(&:id)
        end

        let(:pending_prs) do
          update_jobs.map.with_index do |job, index|
            pr = PendingPullRequest.create!(
              update_job: job,
              updated_dependency_details: [
                {
                  "name" => "business.#{index}",
                  "package_manager" => job.package_manager,
                  "previous_requirements" => [
                    {
                      "file" => "file",
                      "groups" => ["default"],
                      "requirement" => "~> 1.3.0",
                      "source" => nil,
                    },
                  ],
                  "requirements" => [
                    {
                      "file" => "file",
                      "groups" => ["default"],
                      "requirement" => "~> 1.4.0",
                      "source" => nil,
                    },
                  ],
                  "version" => "1.4.0",
                },
              ],
              sort_key: index + 1,
            )
            pr.encrypted_dependency_files_blob.attach(
              io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
              filename: pr.id,
              content_type: "application/octet-stream",
              identify: false,
            )
            pr.message_data = {
              "commit_message" => "Bump business.#{index} from 1.3.0 to 1.4.0",
              "pr_body" => "Bumps business.#{index} from 1.3.0 to 1.4.0.",
              "pr_title" => "Bump business.#{index} from 1.3.0 to 1.4.0",
            }
            pr
          end
        end

        before do
          allow(PendingPullRequest).to receive(:where).and_return(pending_prs)
          allow(CancelStalePullRequestUpdate).to receive(:perform_later)
          allow(MetricsClient).to receive(:increment)
          allow(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
        end

        it "proceeds with PR combination" do
          expect(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(:perform_later)
          described_class.perform_now(associated_update_job_ids: associated_update_job_ids)
        end
      end

      # Failed terminal states
      include_examples "failed terminal state", :processed_with_errors
      include_examples "failed terminal state", :timed_out
      include_examples "failed terminal state", :cancelled
      include_examples "failed terminal state", :abandoned
      include_examples "failed terminal state", :no_successful_runs
    end
  end
end
