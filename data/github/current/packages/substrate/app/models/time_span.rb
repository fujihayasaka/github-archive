# typed: true
# frozen_string_literal: true
class TimeSpan
  attr_reader :starting, :ending
  def initialize(starting, ending)
    @starting = starting
    @ending = ending
  end

  def duration_seconds
    @ending - @starting
  end

  def duration
    duration_seconds * 1_000
  end

  def ==(other)
    starting == other.starting && ending == other.ending
  end
end
