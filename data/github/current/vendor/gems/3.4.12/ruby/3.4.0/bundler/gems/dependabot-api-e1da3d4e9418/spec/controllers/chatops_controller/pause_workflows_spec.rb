# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:paused) { true }

  let(:aqueduct_url) { "#{Prius.get(:aqueduct_url)}/aqueduct.api.v1.JobQueueService" }

  let(:redis) { Dependabot.redis }

  before do
    stub_request(:post, "#{aqueduct_url}/ListQueues").
      to_return(
        status: 200,
        body: '{"queues": [{"app": "dependabot-api", "name": "default"}]}'
      )
    stub_request(:post, "#{aqueduct_url}/AddPausingRule").to_return(status: 200, body: "{}")
    stub_request(:post, "#{aqueduct_url}/RemovePausingRule").to_return(status: 200, body: "{}")

    allow(NotifyDependabotStatusJob).to receive(:perform_later)
    redis.flushdb
  end

  describe "pause_all" do
    subject(:chat_pause_all) do
      chat "dependabot pause-all", "user", "#dependabot-ops"
    end

    before do
      allow(controller).to receive(:require_fido_2fa).and_return(true)
      ProcessorManager.processor_slug_list.each do |processor|
        refute ProcessorManager.paused?(processor)
      end
    end

    it "pauses all Aqueduct queues" do
      chat_pause_all

      expect(chatop_response).to include("default | paused")
    end

    it "pauses all hydro consumers" do
      chat_pause_all

      ProcessorManager.processor_slug_list.each do |processor|
        assert ProcessorManager.paused?(processor)
      end

      expect(chatop_response).to match(
        /repository_dependency_update\w+| paused/
      )
    end

    it "includes status update instructions" do
      chat_pause_all

      expect(chatop_response).to include(":information_source: *Next Steps*:")
      expect(chatop_response).to include("Update Dependabot status using `.status-internal`")
      expect(chatop_response).to include(".status-internal yellow dependabot Degraded service due to <reason>")
      expect(chatop_response).to include(".status-internal red dependabot Service unavailable")
    end

    it "sets paused status and timestamp in Redis" do
      chat_pause_all

      expect(redis.get("dependabot_paused_status")).to eq("true")
      expect(redis.get("dependabot_pause_timestamp").to_i).to be_within(5).of(Time.current.to_i)
    end

    it "enqueues NotifyDependabotStatusJob" do
      chat_pause_all

      expect(NotifyDependabotStatusJob).to have_received(:perform_later)
    end
  end

  describe "resume_all" do
    subject(:chat_resume_all) do
      chat "dependabot resume-all", "user", "#dependabot-ops"
    end

    let(:paused) { false }

    before do
      allow(controller).to receive(:require_fido_2fa).and_return(true)
      ProcessorManager.pause("all")
    end

    it "unpauses all aqueduct queues" do
      chat_resume_all

      expect(chatop_response).to include("default | active")
    end

    it "unpauses all hydro consumers" do
      chat_resume_all

      ProcessorManager.processor_slug_list.each do |processor|
        refute ProcessorManager.paused?(processor)
      end

      expect(chatop_response).to match(
        /repository_dependency_update\w+| processing/
      )
    end

    it "includes status clear instructions" do
      chat_resume_all

      expect(chatop_response).to include(":information_source: *Next Steps*:")
      expect(chatop_response).to include("Clear the status by running the following command:")
      expect(chatop_response).to include(".status-internal clear dependabot Dependabot is back to normal service.")
    end

    it "clears paused status and timestamp in Redis" do
      chat_resume_all

      expect(redis.get("dependabot_paused_status")).to eq("false")
      expect(redis.get("dependabot_pause_timestamp")).to be_nil
    end
  end
end
