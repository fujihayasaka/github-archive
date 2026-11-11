# frozen_string_literal: true

require "rails_helper"
require_relative "../shared_examples/application_processor"

RSpec.describe RepositoryDependencyUpdate::CleanedUpProcessor do
  let(:processor) { described_class.new }

  let(:decoded_payload) do
    hydro_fixture(
      name: "default",
      schema: "github.v1.RepositoryDependencyUpdateCleanedUp"
    )
  end
  let(:github_repo_id) do
    decoded_payload[:repository][:id]
  end
  let(:github_request_id) do
    decoded_payload[:repository_dependency_update][:id]
  end

  let(:consumer) do
    Dependabot.hydro_consumer(processor.options)
  end

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: "mock",
    )
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_repository_dependency_update_cleaned_up" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  def process_with_consumer
    processor.process_with_consumer(message, consumer)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_repository_dependency_update_cleaned_up")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.RepositoryDependencyUpdateCleanedUp\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  it_behaves_like "an application processor"

  context "when neither the Update id or Repository id exists in Dependabot" do
    let(:expected_tags) do
      {
        update_job_state: "missing",
        update_config_state: "missing",
        repository: "missing",
        pending_pull_request: false,
        pending_pull_request_state: "missing",
        pull_request: false,
        package_manager: "unknown",
        last_update_job_error: "missing",
        trigger: "scan",
      }
    end

    it "instruments everything as missing" do
      expect(MetricsClient).to receive(:increment).
        with("dependency_update.cleaned_up", tags: expected_tags)

      process_with_consumer
    end
  end

  context "when only the Repository id exists in Dependabot" do
    let(:repo) do
      FactoryBot.create(:repo, github_id: github_repo_id)
    end

    let(:expected_tags) do
      {
        update_job_state: "missing",
        update_config_state: "missing",
        repository: "active",
        pending_pull_request: false,
        pending_pull_request_state: "missing",
        pull_request: false,
        package_manager: "unknown",
        last_update_job_error: "missing",
        trigger: "scan",
      }
    end

    before do
      FactoryBot.create(:update_config, :active, repo: repo)
    end

    it "instruments the job as missing but repository present" do
      expect(MetricsClient).to receive(:increment).
        with("dependency_update.cleaned_up", tags: expected_tags)

      process_with_consumer
    end
  end

  context "when the Update id has a corresponding job in Dependabot" do
    let(:repo) do
      FactoryBot.create(:repo, github_id: github_repo_id)
    end

    let(:update_config) do
      FactoryBot.create(:update_config, :active, repo: repo)
    end

    context "when the job is stuck in pending" do
      let(:expected_tags) do
        {
          update_job_state: "pending",
          update_config_state: "active",
          repository: "active",
          pending_pull_request: false,
          pending_pull_request_state: "missing",
          pull_request: false,
          package_manager: "bundler",
          last_update_job_error: "missing",
          trigger: "scan",
        }
      end

      before do
        FactoryBot.create(:update_job, github_request_id: github_request_id,
                                       update_config: update_config)
      end

      it "instruments it as pending" do
        expect(MetricsClient).to receive(:increment).
          with("dependency_update.cleaned_up", tags: expected_tags)

        process_with_consumer
      end

      context "and the update config is deleted" do
        let(:expected_tags) do
          {
            update_job_state: "pending",
            update_config_state: "deleted",
            repository: "inactive",
            pending_pull_request: false,
            pending_pull_request_state: "missing",
            pull_request: false,
            package_manager: "bundler",
            last_update_job_error: "missing",
            trigger: "scan",
          }
        end

        before do
          update_config.transition_to!(:deleted)
        end

        it "instruments it as pending with an inactive repository" do
          expect(MetricsClient).to receive(:increment).
            with("dependency_update.cleaned_up", tags: expected_tags)

          process_with_consumer
        end
      end
    end

    context "when the job is stuck in enqueued" do
      let(:expected_tags) do
        {
          update_job_state: "enqueued",
          update_config_state: "active",
          repository: "active",
          pending_pull_request: false,
          pending_pull_request_state: "missing",
          pull_request: false,
          package_manager: "bundler",
          last_update_job_error: "missing",
          trigger: "scan",
        }
      end

      before do
        FactoryBot.create(:update_job, :enqueued,
                          github_request_id: github_request_id,
                          update_config: update_config)
      end

      it "instruments it as enqueued" do
        expect(MetricsClient).to receive(:increment).
          with("dependency_update.cleaned_up", tags: expected_tags)

        process_with_consumer
      end
    end

    context "when the job is stuck in processing" do
      let(:expected_tags) do
        {
          update_job_state: "processing",
          update_config_state: "active",
          repository: "active",
          pending_pull_request: false,
          pending_pull_request_state: "missing",
          pull_request: false,
          package_manager: "bundler",
          last_update_job_error: "missing",
          trigger: "scan",
        }
      end

      before do
        FactoryBot.create(:update_job, :processing,
                          github_request_id: github_request_id,
                          update_config: update_config)
      end

      it "instruments it as processing" do
        expect(MetricsClient).to receive(:increment).
          with("dependency_update.cleaned_up", tags: expected_tags)

        process_with_consumer
      end
    end

    context "when the job has been processed" do
      let!(:update_job) do
        FactoryBot.create(:update_job, :processed,
                          github_request_id: github_request_id,
                          update_config: update_config)
      end

      context "and there are no pull request objects" do
        let(:expected_tags) do
          {
            update_job_state: "processed",
            update_config_state: "active",
            repository: "active",
            pending_pull_request: false,
            pending_pull_request_state: "missing",
            pull_request: false,
            package_manager: "bundler",
            last_update_job_error: "missing",
            trigger: "scan",
          }
        end

        it "instruments it as processed" do
          expect(MetricsClient).to receive(:increment).
            with("dependency_update.cleaned_up", tags: expected_tags)

          process_with_consumer
        end
      end

      context "and there is a pending pull request" do
        let(:expected_tags) do
          {
            update_job_state: "processed",
            update_config_state: "active",
            repository: "active",
            pending_pull_request: true,
            pending_pull_request_state: "pending",
            pull_request: false,
            package_manager: "bundler",
            last_update_job_error: "missing",
            trigger: "scan",
          }
        end

        before do
          FactoryBot.create(:pending_pull_request, update_job: update_job)
        end

        it "instruments it as processed with a pending pull request" do
          expect(MetricsClient).to receive(:increment).
            with("dependency_update.cleaned_up", tags: expected_tags)

          process_with_consumer
        end
      end

      context "and there is a pull request" do
        let(:expected_tags) do
          {
            update_job_state: "processed",
            update_config_state: "active",
            repository: "active",
            pending_pull_request: false,
            pending_pull_request_state: "missing",
            pull_request: true,
            package_manager: "bundler",
            last_update_job_error: "missing",
            trigger: "scan",
          }
        end

        before do
          FactoryBot.create(:pull_request, update_job: update_job, repo: repo)
        end

        it "instruments it as processed with a pending pull request" do
          expect(MetricsClient).to receive(:increment).
            with("dependency_update.cleaned_up", tags: expected_tags)

          process_with_consumer
        end
      end

      context "and there is an update job error" do
        let(:expected_tags) do
          {
            update_job_state: "processed",
            update_config_state: "active",
            repository: "active",
            pending_pull_request: false,
            pending_pull_request_state: "missing",
            pull_request: false,
            package_manager: "bundler",
            last_update_job_error: "pull_request_creation_halted",
            trigger: "scan",
          }
        end

        before do
          FactoryBot.create(
            :update_job_error,
            update_job: update_job,
            error_type: "pull_request_creation_halted",
          )
        end

        it "instruments it as processed with the last update job error" do
          expect(MetricsClient).to receive(:increment).
            with("dependency_update.cleaned_up", tags: expected_tags)

          process_with_consumer
        end
      end
    end
  end

  describe "unexpected message handling" do
    let(:dead_letter_tags) do
      { consumer: processor.class.options[:group_id] }
    end

    before do
      allow(Failbot).to receive(:report)
    end

    context "with a non-Vulnerability update" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "unexpected_update_reason",
          schema: "github.v1.RepositoryDependencyUpdateCleanedUp"
        )
      end

      it "does not count it as a cleaned up job" do
        expect(MetricsClient).not_to receive(:increment).
          with("dependency_update.cleaned_up", tags: anything)
      end

      it "increments the dead letter count" do
        expect(MetricsClient).to receive(:increment).
          with("consumer.dead_letter", tags: dead_letter_tags)

        process_with_consumer
      end

      it "raises an exception" do
        expect(Failbot).to receive(:report).once.with(
          RepositoryDependencyUpdate::CleanedUpHandler::UnexpectedMessageError,
          {
            rollup: "e56588f68c6c6cf60a7f938e318f4479",
            transaction: "RepositoryDependencyUpdate::CleanedUpProcessor",
          }
        )

        processor.process_with_consumer(message, consumer)
      end

      it "discards the erroneous message" do
        expect(consumer).to receive(:mark_message_as_processed).
          with(message)

        processor.process_with_consumer(message, consumer)
      end
    end

    context "with an unexpected error_type" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "unexpected_error_type",
          schema: "github.v1.RepositoryDependencyUpdateCleanedUp"
        )
      end

      it "does not count it as a cleaned up job" do
        expect(MetricsClient).not_to receive(:increment).
          with("dependency_update.cleaned_up", tags: anything)
      end

      it "increments the dead letter count" do
        expect(MetricsClient).to receive(:increment).
          with("consumer.dead_letter", tags: dead_letter_tags)

        processor.process_with_consumer(message, consumer)
      end

      it "raises an exception" do
        expect(Failbot).to receive(:report).once

        processor.process_with_consumer(message, consumer)
      end

      it "discards the erroneous message" do
        expect(consumer).to receive(:mark_message_as_processed).
          with(message)

        processor.process_with_consumer(message, consumer)
      end
    end
  end
end
