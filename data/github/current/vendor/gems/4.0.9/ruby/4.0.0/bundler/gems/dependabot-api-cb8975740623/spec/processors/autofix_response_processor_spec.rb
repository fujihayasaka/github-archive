# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutofixResponseProcessor do
  include ActiveJob::TestHelper

  let(:processor) { described_class.new }
  let(:consumer) { Dependabot.hydro_consumer(processor.options) }
  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: "mock",
      headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
    )
  end

  let(:autofix_suggestion_job) do
    FactoryBot.create(:autofix_suggestion_job, :with_sarif, pull_request: pull_request)
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_autofix_response" }
  end

  let(:pull_request) do
    FactoryBot.create(:pull_request)
  end
  let(:twirp_autofix_client) do
    instance_double(
      GitHub::Twirp::Autofix,
      create_suggested_fix_annotation: true
    )
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
    allow(Dependabot::Application).
      to receive(:autofix_client).
      and_return(twirp_autofix_client)
    allow(twirp_autofix_client).
      to receive(:create_suggested_fix_annotation).with(anything).and_return(true)

    allow(AutofixSuggestionJob).to receive(:find).
      with(autofix_suggestion_job.id).
      and_return(autofix_suggestion_job)
    allow(autofix_suggestion_job).to receive(:complete_github_check_run)
  end

  shared_examples "an instrumented message" do
    it "increments start and complete events with the expected tags" do
      perform_enqueued_jobs(only: [CreateAutofixAnnotationJob]) do
        processor.process_with_consumer(message, consumer)
      end

      expect(MetricsClient).to have_received(:increment).
        with("consumer.process_message.started",
             tags: expected_tags)

      expect(MetricsClient).to have_received(:increment).
        with("consumer.process_message.completed",
             tags: expected_tags)
    end
  end

  shared_examples "an autofix result workflow" do
    context "the autofix response is received an a background job is enqueued" do
      it "starts an autofix suggestion result job and marks the message as read" do
        expect(SuggestedFix.exists?(autofix_suggestion_job_id: autofix_suggestion_job.id)).to be(false)
        expect(consumer).to receive(:mark_message_as_processed).with(message)

        perform_enqueued_jobs(only: [CreateAutofixAnnotationJob]) do
          processor.process_with_consumer(message, consumer)
        end

        expect(SuggestedFix.exists?(autofix_suggestion_job_id: autofix_suggestion_job.id)).to be(true)
      end
    end
  end

  context "with a valid push message for an npm autofix result" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "push_js_fix",
        schema: "code_scanning.v0.DependabotAutofixResult"
      )
    end

    before do
      decoded_payload[:request_id] = autofix_suggestion_job.id
    end

    it_behaves_like "an instrumented message"
    it_behaves_like "an autofix result workflow"
  end

  describe "configuration" do
    subject(:config) do
      processor.options
    end

    it "is correctly configured" do
      expect(config[:group_id]).to eql("dependabot_api_autofix_response")
      expect(config[:subscribe_to]).to eql(/code_scanning\.v0\.DependabotAutofixResult\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end
end
