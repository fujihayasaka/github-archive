# typed: true
# frozen_string_literal: true

module Eventer
  class Timespan
    class_attribute :duration
    attr_reader :beginning, :ending

    def initialize(beginning:, ending:)
      @beginning = beginning
      @ending = ending
    end

    def to_range
      @beginning..@ending
    end

    def duration
      ActiveSupport::Duration.build(@ending - @beginning)
    end

    def group_by(column)
      <<-SQL
    DATE(#{column})
      SQL
    end

    class FullPeriod < Eventer::Timespan
      self.duration = 2.years

      def initialize(*)
        super(
          beginning: self.class.duration.before(Date.today.beginning_of_day),
          ending: Time.now
        )
      end
    end
  end
end
