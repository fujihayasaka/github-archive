# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamuraiFormSignalsTest < GitHub::TestCase

  setup do
    GitHub.stubs(:spamminess_check_enabled?).returns(true)
  end

  test "human submitting form" do
    Timecop.freeze do
      timestamp = Timestamp.milliseconds_since_epoch
      request_params = {
        :timestamp => timestamp,
        :timestamp_secret => SpamuraiFormSignals.timestamp_hmac(timestamp),
        "required_field_1b4c" => "",
      }

      Timecop.travel(21.seconds)

      signals = SpamuraiFormSignals.create(request_params: request_params)
      assert signals.load_to_submit_in_milliseconds >= 20000
      refute_predicate signals, :load_to_submit_timestamp_hacked?
      refute_predicate signals, :load_to_submit_timestamp_missing?
      refute_predicate signals, :load_to_submit_timestamp_secret_missing?
      refute_predicate signals, :honeypot_failure?
    end
  end

  test "hacked timestamp" do
    Timecop.freeze do
      timestamp = Timestamp.milliseconds_since_epoch
      request_params = {
        :timestamp => "1234567890",
        :timestamp_secret => SpamuraiFormSignals.timestamp_hmac(timestamp),
        "required_field_1b4c" => "",
      }

      Timecop.travel(21.seconds)

      signals = SpamuraiFormSignals.create(request_params: request_params)
      assert_nil signals.load_to_submit_in_milliseconds
      assert_predicate signals, :load_to_submit_timestamp_hacked?
      refute_predicate signals, :load_to_submit_timestamp_missing?
      refute_predicate signals, :load_to_submit_timestamp_secret_missing?
      refute_predicate signals, :honeypot_failure?
    end
  end

  test "rolling timestamp secret" do
    Timecop.freeze do
      begin
        GitHub.stubs(:spamurai_timestamp_secrets).returns(%w[1234 abcd])

        timestamp = Timestamp.milliseconds_since_epoch
        request_params = {
          :timestamp => timestamp,
          :timestamp_secret => SpamuraiFormSignals.timestamp_hmac(timestamp, "abcd"),
          "required_field_1b4c" => "",
        }
        signals = SpamuraiFormSignals.create(request_params: request_params)
        refute_predicate signals, :load_to_submit_timestamp_hacked?
      end
    end
  end

  test "missing timestamp" do
    Timecop.freeze do
      timestamp = Timestamp.milliseconds_since_epoch
      request_params = {
        :timestamp_secret => SpamuraiFormSignals.timestamp_hmac(timestamp),
        "required_field_1b4c" => "",
      }

      Timecop.travel(21.seconds)

      signals = SpamuraiFormSignals.create(request_params: request_params)
      assert_nil signals.load_to_submit_in_milliseconds
      refute_predicate signals, :load_to_submit_timestamp_hacked?
      assert_predicate signals, :load_to_submit_timestamp_missing?
      refute_predicate signals, :load_to_submit_timestamp_secret_missing?
      refute_predicate signals, :honeypot_failure?
    end
  end

  test "missing timestamp_secret" do
    Timecop.freeze do
      timestamp = Timestamp.milliseconds_since_epoch
      request_params = {
        :timestamp => timestamp,
        "required_field_1b4c" => "",
      }

      Timecop.travel(21.seconds)

      signals = SpamuraiFormSignals.create(request_params: request_params)
      assert_nil signals.load_to_submit_in_milliseconds
      refute_predicate signals, :load_to_submit_timestamp_hacked?
      refute_predicate signals, :load_to_submit_timestamp_missing?
      assert_predicate signals, :load_to_submit_timestamp_secret_missing?
      refute_predicate signals, :honeypot_failure?
    end
  end

  test "honeypot failure" do
    Timecop.freeze do
      timestamp = Timestamp.milliseconds_since_epoch
      request_params = {
        :timestamp => timestamp,
        :timestamp_secret => SpamuraiFormSignals.timestamp_hmac(timestamp),
        "required_field_1b4c" => "me-bad-guy",
      }

      Timecop.travel(21.seconds)

      signals = SpamuraiFormSignals.create(request_params: request_params)
      assert signals.load_to_submit_in_milliseconds >= 20000
      refute_predicate signals, :load_to_submit_timestamp_hacked?
      refute_predicate signals, :load_to_submit_timestamp_missing?
      refute_predicate signals, :load_to_submit_timestamp_secret_missing?
      assert_predicate signals, :honeypot_failure?
    end
  end
end
