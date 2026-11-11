# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyDependabotStatusJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  let(:channel) { "#dependabot-ops" }
  let(:chatops_controller) { instance_double(ChatopsController) }
  let(:redis) { Dependabot.redis }

  before do
    allow(ChatopsController).to receive(:new).and_return(chatops_controller)
    allow(chatops_controller).to receive(:jsonrpc_success)
    allow(Dependabot::Logger).to receive(:info)
    redis.flushdb
  end

  context "when Dependabot is paused and within validity period" do
    before do
      redis.set("dependabot_paused_status", "true")
      redis.set("dependabot_pause_timestamp", 1.day.ago.to_i)
    end

    it "sends a paused status notification" do
      job.perform_now

      expect(chatops_controller).to have_received(:jsonrpc_success).with(
        ":information_source: Dependabot is currently paused. " \
        "Status updates will continue every #{NotifyDependabotStatusJob::NOTIFY_DEPENDABOT_RETRY_INTERVAL.inspect} " \
        "until resumed.",
        options: { channel: channel }
      )
    end

    it "re-enqueues the job for the next notification" do
      expect { job.perform_now }.to have_enqueued_job(described_class).at_least(:once)
    end
  end

  context "when Dependabot is paused but validity period has expired" do
    before do
      redis.set("dependabot_paused_status", "true")
      redis.set("dependabot_pause_timestamp", 3.days.ago.to_i)
    end

    it "sends a validity period expired notification" do
      job.perform_now

      expect(chatops_controller).to have_received(:jsonrpc_success).with(
        ":warning: Dependabot pause validity period has expired. " \
        "Notifications will stop until further action is taken.",
        options: { channel: channel }
      )
    end

    it "does not re-enqueue the job" do
      expect { job.perform_now }.not_to have_enqueued_job(described_class)
    end
  end

  context "when Dependabot is resumed" do
    before do
      redis.set("dependabot_paused_status", "false")
    end

    it "sends a resumed notification" do
      job.perform_now

      expect(chatops_controller).to have_received(:jsonrpc_success).with(
        ":white_check_mark: Dependabot has been resumed. Regular status notifications have stopped.",
        options: { channel: channel }
      )
    end

    it "does not re-enqueue the job" do
      expect { job.perform_now }.not_to have_enqueued_job(described_class)
    end
  end
end
