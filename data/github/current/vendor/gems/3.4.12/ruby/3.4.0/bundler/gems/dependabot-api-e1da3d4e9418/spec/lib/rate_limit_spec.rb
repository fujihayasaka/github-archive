# frozen_string_literal: true

require "rails_helper"
require "rate_limit"

RSpec.describe RateLimit do
  include ActiveSupport::Testing::TimeHelpers

  let(:rate_limit) { described_class.new(8, 1.second) }

  it "splits the frequency into the limit count" do
    expect(rate_limit.ticket_interval).to eq(1 / 8.0)
  end

  it "is current until the next cycle based on the frequency" do
    freeze_time do
      expect(rate_limit).to be_current
    end
  end

  it "is not current after the frequency" do
    rate_limit
    travel_to(Time.zone.now + 2.seconds) do
      expect(rate_limit).not_to be_current
    end
  end

  it "is current after a refresh" do
    rate_limit
    travel_to(Time.zone.now + 2.seconds) do
      rate_limit.refresh
      expect(rate_limit).to be_current
    end
  end

  it "is always unlocked" do
    expect(rate_limit).not_to be_locked

    rate_limit.lock(reason: "bees in the data centre")

    expect(rate_limit).not_to be_locked

    rate_limit.unlock!

    expect(rate_limit).not_to be_locked
  end
end
