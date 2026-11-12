# frozen_string_literal: true

require "rails_helper"
require "throttler"

RSpec.describe Throttler do
  include ActiveSupport::Testing::TimeHelpers

  # Max cycles the throttler will make for testing
  let(:max_cycles) { 1 }

  let(:rate_limit) do
    RateLimit.new(tickets_per_freq, frequency)
  end

  let(:throttler) do
    described_class.new(redis, "test", rate_limit, max_cycles: max_cycles, timeout: 1)
  end

  # Clean redis, as the tickets are stored there
  let(:redis) { Dependabot.redis }

  before do
    redis.flushdb
  end

  describe "::build" do
    let(:mock_production_string) { ActiveSupport::StringInquirer.new("production") }
    let(:throttler) { described_class.build("test") }

    context "default" do
      it { expect(throttler).to be_instance_of(Throttler::Open) }
      it { expect(throttler.rate_limit).to be_nil }
    end

    context "for production enviroments", :cloud do
      before { allow(Rails).to receive(:env).and_return(mock_production_string) }

      it { expect(throttler).to be_instance_of(described_class) }
      it { expect(throttler.rate_limit).to be_instance_of(RedisRateLimit) }
    end

    context "for enterprise production enviroments", :enterprise do
      before { allow(Rails).to receive(:env).and_return(mock_production_string) }

      it { expect(throttler).to be_instance_of(Throttler::Open) }
      it { expect(throttler.rate_limit).to be_nil }
    end
  end

  context "print_tickets" do
    let(:frequency) { 1.second }
    let(:tickets_per_freq) { 5 }
    let(:max_cycles) { 2 }

    let(:throttler1) do
      described_class.new(redis,
                          "test",
                          rate_limit,
                          max_cycles: max_cycles,
                          timeout: 1)
    end

    let(:throttler2) do
      described_class.new(redis,
                          "test",
                          rate_limit,
                          max_cycles: max_cycles,
                          timeout: 1)
    end

    it "writes and burns tickets to a distinct, private node key" do
      throttler1.print_tickets
      expect(redis.llen(throttler1.ticket_key)).to eq 5

      expect(redis.llen(throttler2.ticket_key)).to eq 0
    end

    it "makes itself the leader if there is no leader" do
      expect do
        throttler1.print_tickets
      end.to change(throttler1, :current_leader).
        from(nil).to(throttler1.uuid)
    end

    it "sets leadership to expire" do
      throttler1.print_tickets

      # -1 indicates a non-expiring key, so long as the TLL is over 0
      # and less than or equal to 2 * frequency, it is working correctly
      expect(redis.ttl(throttler1.leader_key)).to be_between(0, 2)
    end

    it "does not make itself leader if another leads" do
      redis.lpush(throttler1.leader_key, throttler1.uuid)

      expect do
        throttler2.print_tickets
      end.not_to change(throttler2, :current_leader).from(throttler1.uuid)
    end

    it "renews leadership if it leads" do
      # Set a permenant value to verify we update the existing key
      # after testing it
      redis.lpush(throttler1.leader_key, throttler1.uuid)
      expect(redis.ttl(throttler1.leader_key)).to be(-1)

      expect do
        throttler1.print_tickets
      end.not_to change(throttler1, :current_leader).from(throttler1.uuid)

      # Ensure we've set the permenant key to become an expiring one
      expect(redis.ttl(throttler1.leader_key)).to be_between(0, 2)
    end
  end

  context "print_ticket" do
    let(:frequency) { 1.second }
    let(:tickets_per_freq) { 1 }

    it "pushes one ticket to redis" do
      throttler.print_ticket

      expect(redis.lpop(throttler.ticket_key)).not_to be nil
      expect(redis.lpop(throttler.ticket_key)).to be nil
    end
  end

  context "leader_key" do
    let(:frequency) { 1.second }
    let(:tickets_per_freq) { 5 }

    let(:throttler1) do
      described_class.new(redis, "test-a", rate_limit, timeout: 1)
    end

    let(:throttler2) do
      described_class.new(redis, "test-b", rate_limit, timeout: 1)
    end

    it "use a distinct leader key for each throttler name" do
      expect(throttler1.leader_key).not_to eql(throttler2.leader_key)
    end
  end

  context "new_with_redis_limit" do
    let(:throttler) { described_class.new_with_redis_limit(redis, "test") }

    it "creates a throttler using redis rate limit" do
      expect(throttler.rate_limit).to be_instance_of(RedisRateLimit)
    end
  end

  context "when not setting max_cycles" do
    let(:throttler) do
      described_class.new(redis, "test", RateLimit.new(1, 1.minute), timeout: 1)
    end

    it "loops" do
      expect do
        Timeout.timeout(0.1) { throttler.print_tickets }
      end.to raise_error(Timeout::Error)
    end
  end

  context "throttle" do
    let(:throttler) do
      described_class.new(redis, "test", RateLimit.new(100, 1.second), timeout: 1)
    end

    context "when there is no leader" do
      before { throttler.print_ticket }

      it "blocks waiting for a leader to be elected" do
        expect do
          throttler.throttle { 1 }
        end.to raise_error(Throttler::TimeoutError)
      end

      it "defaults to a nil leader ticket key" do
        expect(throttler.leader_ticket_key).to be_nil
      end
    end

    context "when there is a leader" do
      before { throttler.take_leadership }

      context "when there is a ticket" do
        before { throttler.print_ticket }

        it "proceeds" do
          value = false
          expect do
            throttler.throttle { value = true }
          end.to change { value }.from(false).to(true)
        end
      end

      context "when there is no ticket" do
        it "blocks waiting for a ticket to be printed" do
          expect do
            throttler.throttle { 1 }
          end.to raise_error(Throttler::TimeoutError)
        end
      end

      context "when there is a ticket, but it belongs to a non-leader" do
        let(:follower_throttler) do
          described_class.new(redis, "test", RateLimit.new(100, 1.second), timeout: 1)
        end

        before { follower_throttler.print_ticket }

        it "blocks waiting for a ticket to be printed" do
          expect do
            throttler.throttle { 1 }
          end.to raise_error(Throttler::TimeoutError)
        end
      end
    end
  end

  context "when waiting too long to use the ticket" do
    let(:rate_limit) { RateLimit.new(1, 1.second) }
    let(:throttler) do
      described_class.new(redis, "test", rate_limit, timeout: 1,
                                                     max_cycles: max_cycles)
    end

    before do
      allow(rate_limit).to receive(:current?).and_return(true, true, false)
      travel_to(Time.zone.now - 1.hour) { throttler.print_tickets }
    end

    it "has been expired" do
      expect do
        throttler.throttle { 1 }
      end.to raise_error(Throttler::TimeoutError)
    end
  end
end
