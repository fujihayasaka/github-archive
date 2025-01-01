# typed: true
# frozen_string_literal: true

require "test_helper"

class TimeSpanTest < GitHub::TestCase
  setup do
    @starting = 0
    @ending = 0
  end

  test "duration_seconds" do
    @starting = 10
    @ending = 52
    assert_equal 42, time_span.duration_seconds
  end

  test "duration" do
    @starting = 20
    @ending = 63
    assert_equal 43000, time_span.duration
  end

  test "starting" do
    @starting = 10
    assert_equal 10, time_span.starting
  end

  test "ending" do
    @ending = 20
    assert_equal 20, time_span.ending
  end

  def time_span
    @time_span ||= TimeSpan.new(@starting, @ending)
  end
end
