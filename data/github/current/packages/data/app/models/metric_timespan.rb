# typed: true
# frozen_string_literal: true

class MetricTimespan
  include Enumerable

  class_attribute :period, :duration, :bucket_duration, instance_writer: false

  alias_method :to_param, :period

  class Week < MetricTimespan
    self.period = :week
    self.duration = 1.week
    self.bucket_duration = 1.day

    def group_by(column)
      <<-SQL
      CAST(UNIX_TIMESTAMP(DATE(#{column})) as SIGNED)
      SQL
    end
  end

  class Month < MetricTimespan
    self.period = :month
    self.duration = 1.month
    self.bucket_duration = 1.day

    def group_by(column)
      <<-SQL
      CAST(UNIX_TIMESTAMP(DATE(#{column})) as SIGNED)
      SQL
    end
  end

  class Year < MetricTimespan
    self.period = :year
    self.duration = 1.year
    self.bucket_duration = 1.week

    def initialize(beginning: Time.current.beginning_of_year)
      super
      adjust_week_range
    end

    def group_by(column)
      # Rounded to the start of the week.
      <<-SQL
      CAST(UNIX_TIMESTAMP(DATE_SUB(
        DATE(#{column}),
        INTERVAL (WEEKDAY(#{column})) DAY
      )) as SIGNED)
      SQL
    end

    def title
      "#{@beginning.strftime("%b #{@beginning.day.ordinalize}, %Y")} to #{@ending.strftime("%b #{@ending.day.ordinalize}, %Y")}"
    end

    private

    def adjust_week_range
      # Always start on a monday.
      @beginning = @beginning.beginning_of_week

      # Only use the last full week in the calendar year
      # so we don't over lap with previous year's reaching
      # for monday like above (would make totals off)
      # The +1 moves to the next day thus making the range end-exclusive
      # just like the week/month periods, instead of end_of_day and inclusive.
      @ending = @ending.advance(days: -@ending.wday + 1)
    end
  end

  PERIODS = {
    week: Week,
    month: Month,
    year: Year,
  }

  def self.for(period = :week)
    PERIODS.fetch(period.downcase.to_sym)
  end

  def self.beginning(beginning = Time.zone.today)
    new beginning: beginning
  end

  def self.ending(ending = Time.zone.today)
    new beginning: duration.before(Coerce.to_time ending)
  end

  def initialize(beginning: Time.zone.today.__send__("beginning_of_#{period}"))
    @beginning = Coerce.to_time(beginning)

    @ending = duration.after(@beginning)
  end

  def title
    "#{@beginning.strftime("%b #{@beginning.day.ordinalize}")} to #{@ending.strftime("%b #{@ending.day.ordinalize}")}"
  end

  # Expected to be sorted
  def buckets
    @buckets ||= map(&:to_i)
  end

  def previous
    self.class.new(beginning: duration.before(@beginning))
  end

  def next
    self.class.new(beginning: duration.after(@beginning))
  end

  def ==(other)
    period == other.period &&
      to_range == other.to_range
  end

  def each(&block)
    enum = Enumerator.new do |y|
      current = @beginning

      while current < @ending
        y << current
        current += bucket_duration
      end
    end

    block_given? ? enum.each(&block) : enum
  end

  def to_range
    @beginning..@ending
  end

  def as_json(*)
    {
      period: period,
      beginning: @beginning.to_i * 1000,
      ending: @ending.to_i * 1000,
    }
  end

  def to_s
    [period, @beginning.to_date].join ":"
  end

  module Coerce
    module_function

    def to_time(time)
      case time
      when String then Time.zone.parse(time)
      when Numeric then Time.zone.at(time)
      when Date, DateTime then time.beginning_of_day
      else time.in_time_zone
      end
    end
  end

end
