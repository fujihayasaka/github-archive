# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateLimitBackoffStrategy do
  let(:strategy) { described_class.new(options) }
  let(:attempt) { 1 }
  let(:exception) { RuntimeError.new }

  describe "#should_retry?" do
    subject { strategy.should_retry?(attempt, exception) }

    context "when the limit is infinite" do
      let(:options) { { limit: nil, unlimited_retries: true } }

      it "is true on 1st attempt" do
        expect(strategy.should_retry?(1, exception)).to eq(true)
      end

      it "is true on 99,999th attempt" do
        expect(strategy.should_retry?(99_999, exception)).to eq(true)
      end
    end

    context "when the limit is 0" do
      let(:options) { { limit: 0 } }

      it "is false on 1st attempt" do
        expect(strategy.should_retry?(1, exception)).to eq(false)
      end

      it "is false on 99,999th attempt" do
        expect(strategy.should_retry?(99_999, exception)).to eq(false)
      end
    end

    context "when the limit is 5" do
      let(:options) { { limit: 5 } }

      it "is true on 1st attempt" do
        expect(strategy.should_retry?(1, exception)).to eq(true)
      end

      it "is true on 4th attempt" do
        expect(strategy.should_retry?(4, exception)).to eq(true)
      end

      it "is false on 5th attempt" do
        expect(strategy.should_retry?(99_999, exception)).to eq(false)
      end
    end

    context "with retryable_exceptions" do
      let(:options) { { limit: 10, retryable_exceptions: [RuntimeError] } }

      it "retries retriable exceptions" do
        expect(strategy.should_retry?(1, RuntimeError.new)).to eq(true)
      end

      it "retries retriable exception subclasses" do
        expect(strategy.should_retry?(1, Class.new(RuntimeError).new)).to eq(true)
      end

      it "does not retry other exceptions" do
        expect(strategy.should_retry?(1, Exception.new)).to eq(false)
      end
    end

    context "with fatal_exceptions" do
      let(:options) { { limit: 10, fatal_exceptions: [RuntimeError] } }

      it "does not retry fatal exceptions" do
        expect(strategy.should_retry?(1, RuntimeError.new)).to eq(false)
      end

      it "does not retry fatal exception subclasses" do
        expect(strategy.should_retry?(1, Class.new(RuntimeError).new)).to eq(false)
      end

      it "retries other exceptions" do
        expect(strategy.should_retry?(1, Exception.new)).to eq(true)
      end
    end
  end

  describe "#retry_delay" do
    let(:exception) { RuntimeError.new }

    context "limited retries" do
      let(:options) { { limit: 5 } }

      it "returns value greater than previous for first attempt" do
        attempt_1_delay = strategy.retry_delay(1, exception)
        attempt_3_delay = strategy.retry_delay(3, exception)
        expect(attempt_1_delay).to be < attempt_3_delay
      end

      it "returns value greater than previous for fifth attempt" do
        attempt_3_delay = strategy.retry_delay(3, exception)
        attempt_5_delay = strategy.retry_delay(5, exception)
        expect(attempt_3_delay).to be < attempt_5_delay
      end
    end

    context "unlimited retries" do
      let(:options) { { limit: nil, unlimited_retries: true } }

      specify { expect { strategy.retry_delay(1000, exception) }.not_to raise_error }
    end

    described_class::RATE_LIMITED_ERRORS.each do |exception_cls|
      context "when rate limited exception #{exception_cls}" do
        let(:options) { { limit: 5 } }
        let(:reset_at) { 1.hour.from_now.to_i }

        let(:exception) do
          exception_cls.new(
            response_headers: {
              "X-RateLimit-Reset" => reset_at,
            },
          )
        end

        it "returns value greater than the reset for attempt 1" do
          attempt_1_delay = strategy.retry_delay(1, exception)
          reset_in = Time.at(reset_at).in_time_zone - Time.now.in_time_zone
          expect(attempt_1_delay).to be > reset_in
        end

        it "returns value greater than the reset for attempt 100" do
          attempt_1_delay = strategy.retry_delay(1, exception)
          attempt_100_delay = strategy.retry_delay(100, exception)
          expect(attempt_100_delay).to be > attempt_1_delay
        end

        context "when reset is in the past" do
          let(:reset_at) { 1.hour.ago.to_i }

          it "returns value gte the baseline" do
            expect(strategy.retry_delay(1, exception)).to be >= 18
          end
        end

        context "when reset is not set" do
          let(:reset_at) { nil }

          it "returns value gte the baseline" do
            expect(strategy.retry_delay(1, exception)).to be >= 18
          end
        end
      end
    end
  end
end
