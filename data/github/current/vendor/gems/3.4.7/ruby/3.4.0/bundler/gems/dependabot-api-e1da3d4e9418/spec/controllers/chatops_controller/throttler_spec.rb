# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "throttler_status" do
    let(:throttler) do
      Throttler.new_with_redis_limit(Throttler.redis, "test:gh:pr")
    end

    before do
      allow(Throttlers).to receive(:pull_request) { throttler }
    end

    it "shows the status of the throttlers" do
      chat "dependabot throttler-status", "user", "#dependabot-ops"

      expect(chatop_response).
        to match(/PR creation limited to \d+ requests per \d+ seconds/)
    end

    it "shows the reason when locked" do
      throttler.rate_limit.lock(reason: "bees everywhere")

      chat "dependabot throttler-status", "user", "#dependabot-ops"

      expect(chatop_response).
        to include("PR creation rate limit is currently locked: "\
                   "bees everywhere")

      throttler.rate_limit.unlock!
    end
  end

  describe "throttler_set" do
    let(:throttler) do
      Throttler.new_with_redis_limit(Throttler.redis, "test:gh:pr")
    end

    def assert_throttler_defaults
      assert throttler.rate_limit.limit, 5
      assert throttler.rate_limit.frequency, 2
    end

    before do
      allow(controller).to receive(:require_fido_2fa).and_return(true)
      allow(Throttlers).to receive(:pull_request) do
        throttler
      end

      assert_throttler_defaults
    end

    it "updates the throttler rate limit" do
      chat "dependabot throttler-set 10 per 5 seconds",
           "user",
           "#dependabot-ops"

      assert throttler.rate_limit.limit, 10
      assert throttler.rate_limit.frequency, 5

      expect(chatop_response).
        to match(/PR creation rate limit updated to 10 requests per 5 seconds/)
    end

    it "does not accept zero values" do
      chat "dependabot throttler-set 0 per 2 sec", "user", "#dependabot-ops"

      assert_throttler_defaults

      expect(chatop_error).
        to match(/Invalid rate limit of 0 requests per 2 seconds/)

      chat "dependabot throttler-set 5 per 0 sec", "user", "#dependabot-ops"

      assert_throttler_defaults

      expect(chatop_error).
        to match(/Invalid rate limit of 5 requests per 0 seconds/)

      chat "dependabot throttler-set 0 per 0 seconds", "user", "#dependabot-ops"

      assert_throttler_defaults

      expect(chatop_error).
        to match(/Invalid rate limit of 0 requests per 0 sec/)
    end

    it "does not allow changes if the throttler rate limit is locked" do
      throttler.rate_limit.lock(reason: "bees everywhere")

      chat "dependabot throttler-set 10 per 5 seconds",
           "user",
           "#dependabot-ops"

      assert_throttler_defaults

      expect(chatop_error).
        to match(/PR creation rate limit is currently locked: bees everywhere/)

      throttler.rate_limit.unlock!
    end
  end

  describe "throttler_lock" do
    let(:throttler) do
      Throttler.new_with_redis_limit(Throttler.redis, "test:gh:pr")
    end

    let(:rate_limit) do
      throttler.rate_limit
    end

    before do
      allow(controller).to receive(:require_fido_2fa).and_return(true)
      allow(Throttlers).to receive(:pull_request) do
        throttler
      end
    end

    after do
      rate_limit.unlock!
    end

    it "locks the throttler rate limit with a reason" do
      chat "dependabot throttler-lock bees everywhere!",
           "user",
           "#dependabot-ops"

      expect(rate_limit).to be_locked
      expect(rate_limit.lock_reason).to eql("bees everywhere!")

      expect(chatop_response).to include(
        "I have locked the PR creation rate limit"
      )
    end

    it "backs off if the rate limit is already locked" do
      rate_limit.lock(reason: "we've got ants all over the place")

      chat "dependabot throttler-lock bees everywhere!",
           "user",
           "#dependabot-ops"

      expect(rate_limit).to be_locked
      expect(rate_limit.lock_reason).
        to eql("we've got ants all over the place")

      expect(chatop_response).to include(
        "PR creation rate limit already locked: "\
        "we've got ants all over the place"
      )
    end
  end

  describe "throttler_unlock" do
    let(:throttler) do
      Throttler.new_with_redis_limit(Throttler.redis, "test:gh:pr")
    end

    let(:rate_limit) do
      throttler.rate_limit
    end

    before do
      allow(controller).to receive(:require_fido_2fa).and_return(true)
      allow(Throttlers).to receive(:pull_request) do
        throttler
      end
    end

    after do
      rate_limit.unlock!
    end

    it "succeeds when locked" do
      rate_limit.lock(reason: "bees and ants!")

      chat "dependabot throttler-unlock", "user", "#dependabot-ops"

      expect(rate_limit).not_to be_locked

      expect(chatop_response).to include(
        "I have unlocked the PR creation rate limit"
      )
    end

    it "succeeds when unlocked" do
      rate_limit.unlock!

      chat "dependabot throttler-unlock", "user", "#dependabot-ops"

      expect(rate_limit).not_to be_locked

      expect(chatop_response).to include(
        "I have unlocked the PR creation rate limit"
      )
    end
  end
end
