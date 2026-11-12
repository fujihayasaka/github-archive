# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe GitHubActionComputeUsageProcessor do
  let(:processor) { described_class.new }
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
      headers: {},
    )
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_actions_compute_usage" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_actions_compute_usage")
      expect(config[:subscribe_to]).
        to eql(/github\.actions\.v0\.ComputeUsage\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  describe "with a properly configured message" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "default",
        schema: "github.actions.v0.ComputeUsage"
      )
    end

    let(:invoking_user_id) do
      decoded_payload[:invoking_user_id]
    end

    def process_with_consumer
      processor.process_with_consumer(message, consumer)
    end

    it_behaves_like "an application processor"

    context "when the compute usage event has completed with a conclusion of success" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "default",
          schema: "github.actions.v0.ComputeUsage"
        ).tap do |payload|
          payload[:check_run_conclusion] = :RESULT_SUCCESS
        end
      end

      it "does not enqueue a handler job" do
        expect { process_with_consumer }.not_to have_enqueued_job(HandleFailedActionRunJob)
      end
    end

    context "when the compute usage event has completed with a conclusion of failure" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "default",
          schema: "github.actions.v0.ComputeUsage"
        ).tap do |payload|
          payload[:check_run_conclusion] = :RESULT_FAILURE
        end
      end

      it "enqueues a handler job" do
        expect { process_with_consumer }.to have_enqueued_job(HandleFailedActionRunJob).with(
          workflow_run_id: decoded_payload[:workflow_run_id],
          workflow_job_conclusion: decoded_payload[:check_run_conclusion]
        )
      end
    end

    context "when the compute usage event has completed with failure, but wasn't triggered by Dependabot" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "default",
          schema: "github.actions.v0.ComputeUsage"
        ).tap do |payload|
          payload[:check_run_conclusion] = :RESULT_FAILURE
          payload[:invoking_user_id] = 33559333
        end
      end

      it "does not enqueue a handler job" do
        expect { process_with_consumer }.not_to have_enqueued_job(HandleFailedActionRunJob)
      end
    end

    context "when the compute usage event wasn't from a dynamic event" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "default",
          schema: "github.actions.v0.ComputeUsage"
        ).tap do |payload|
          payload[:invoking_event_type] = "push"
        end
      end

      it "does not enqueue a handler job" do
        expect { process_with_consumer }.not_to have_enqueued_job(HandleFailedActionRunJob)
      end
    end

    %w(
      RESULT_UNKNOWN
      RESULT_CANCELLED
      RESULT_PARTIALLY_SUCCEEDED
      RESULT_SKIPPED
      stale
    ).each do |conclusion|
      context "when the compute usage event has completed with a conclusion of '#{conclusion}'" do
        let(:decoded_payload) do
          hydro_fixture(
            name: "default",
            schema: "github.actions.v0.ComputeUsage"
          ).tap do |payload|
            payload[:check_run_conclusion] = conclusion
          end
        end

        it "enqueues a handler job" do
          expect { process_with_consumer }.to have_enqueued_job(HandleFailedActionRunJob).with(
            workflow_run_id: decoded_payload[:workflow_run_id],
            workflow_job_conclusion: decoded_payload[:check_run_conclusion]
          )
        end
      end
    end
  end
end
