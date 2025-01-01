# typed: true
# frozen_string_literal: true
require "test_helper"

class TimestampTest < GitHub::TestCase
  test ".from_time and .to_time are inverse" do
    time = Time.at(1496996321)
    assert_equal 1496996321000, Timestamp.from_time(time)
    assert_equal time, Timestamp.to_time(Timestamp.from_time(time))
  end

  test ".milliseconds_since_epoch uses local time by default" do
    now = DateTime.now.utc

    Timecop.freeze(now) do
      assert_equal now.strftime("%s%3N").to_i, Timestamp.milliseconds_since_epoch
    end
  end
end
