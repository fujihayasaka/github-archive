# typed: true
# frozen_string_literal: true

class MemexProject
  # This Comparator class provides more relational operator functionality than the base Comparator does.
  # This class understands the operators: >, >=, <, <=, and .. (inclusive range) when comparing dates.
  class DateComparator < Comparator
    # Defines all the regular expressions that will be used to match against the filter value.  If a
    # regular expression gets a match then the filter will use the matching method for comparison.
    REGEX_TO_RELATIONAL_OP = {
      /\A>=/  => :gteq?,
      /\A<=/  => :lteq?,
      /\A>/   => :gt?,
      /\A</   => :lt?,
      /\.\./  => :between?
    }.freeze

    # If a filter_value does not contain a relational operator then this operator will be used.
    DEFAULT_OP = :eq?

    # Defines the middle character(s) that indicate the filter_value is a range.
    RANGE_SEPARATOR = ".."

    # We do not need to expose the constants in this class as part of our public API.
    private_constant :REGEX_TO_RELATIONAL_OP, :DEFAULT_OP, :RANGE_SEPARATOR

    def sanitize_filter_values(filter_values)
      filter_values.map do |filter_value|
        # The inputted value may or may not contain double quotes, single quotes, and/or wildcard (*).
        # If it does, discard them.
        filter_value
          .to_s
          .tr('"', "")
          .tr("'", "")
          .tr("*", "")
      end
    end

    # Public: main method for comparing a filter and a passed in date.
    #
    # item_value: A string to compare against the filter values.  This string can, but does not have to,
    #             contain a relational operator.  If a relational operator is not present then equality is
    #             assumed.  Examples: ">2020-01-01", ">=2020-01-01", "2020-01-01", "2020-01-01..2020-01-02",
    #
    # Returns true if the item_value matches one of the filter_values, false otherwise.
    def matches?(item_value)
      filter_values.any? do |filter_value|
        method = relational_op_method(filter_value)
        send(method, filter_value, item_value)
      end
    end

    private

    # Naming of the methods loosely-inspired by Arel.
    # https://github.com/rails/rails/blob/v7.0.3.1/activerecord/lib/arel/predications.rb

    def gteq?(filter_value, other_date)
      coerce(other_date) >= coerce(filter_value)
    end

    def lteq?(filter_value, other_date)
      coerce(other_date) <= coerce(filter_value)
    end

    def gt?(filter_value, other_date)
      coerce(other_date) > coerce(filter_value)
    end

    def lt?(filter_value, other_date)
      coerce(other_date) < coerce(filter_value)
    end

    def eq?(filter_value, other_date)
      (coerce(filter_value) == coerce(other_date)) ^ negated
    end

    def between?(filter_value, other_date)
      from_date, to_date = parse_range_dates(filter_value)
      other_date         = coerce(other_date)

      if from_date && to_date
        (other_date <= to_date) && (other_date >= from_date)
      elsif from_date
        (other_date >= from_date)
      elsif to_date
        (other_date <= to_date)
      else
        true
      end
    end

    # Determines which relational method to use for a given filter_value.
    #
    # Examples
    #
    #   relational_op_method("2020-01-01")
    #   # => :eq?
    #
    #   relational_op_method(">2020-01-01")
    #   # => :gt?
    #
    # Returns a symbol representing the method to use for the given filter_value.
    def relational_op_method(filter_value)
      REGEX_TO_RELATIONAL_OP.each do |regex, op|
        return op if filter_value =~ regex
      end

      DEFAULT_OP
    end

    # Take a passed in string filter_value and return an array of two values no matter what the string has.
    #
    # filter_value: A string that contains a date range expression.
    #
    # Examples
    #
    #   parse_range_dates("2020-01-01..2020-01-02")
    #   # => ["2020-01-01", "2020-01-02"]
    #
    #   parse_range_dates("2020-01-01..")
    #   # => ["2020-01-01", nil]
    #
    #   parse_range_dates("..2020-01-02")
    #   # => [nil, "2020-01-02"]
    #
    # Returns an array of two values.  The first value is the from_date and the second value is the to_date.
    def parse_range_dates(filter_value)
      date_values = filter_value.to_s.split(RANGE_SEPARATOR)

      if date_values.length == 0
        date_values = [nil, nil]
      elsif date_values.length == 1
        date_values << nil
      end

      date_values[0..1].map { |date_value| coerce(date_value) }
    end

    # Ensure a passed in value is a date.
    #
    # Examples
    #
    #   coerce("2020-01-01")
    #   # => 2020-01-01
    #
    #   coerce(nil)
    #   # => nil
    #
    # Returns a Date object or nil.
    def coerce(value)
      return unless value

      value.to_date
    end
  end
end
