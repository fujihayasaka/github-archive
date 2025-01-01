# typed: strict
# frozen_string_literal: true

class MemexProject
  # This Comparator class formats iteration ranges and returns the correct query for Elasticsearch.
  # This class understands the operators: >, >=, <, <=, and .. (inclusive range) when comparing strings like "Iteration 1".
  class IterationComparator
    ITERATION_INEQUALITY_REGEX = /
      (?<operator>[><]=?)?\s*  # Optional leading inequality operator (>, >=, < or <=)
      (?<iteration>.+)         # Mandatory iteration identifier
    /x

    # This regex finds an unquoted range operator .. by matching whenever there is an
    # even number of double quotes that appear after the operator.
    #
    # https://stackoverflow.com/a/1191598
    UNQUOTED_RANGE_OPERATOR_REGEX = /\.\.(?=(?:(?:[^"]*+"){2})*+[^"]*+\z)/x

    ITERATION_RANGE_REGEX = /
      (?<start_iteration>.+)                         # Mandatory starting iteration identifier
      (?<operator>#{UNQUOTED_RANGE_OPERATOR_REGEX})  # Mandatory range operator .. itself
      (?<end_iteration>.+)                           # Mandatory ending iteration identifier
    /x

    sig do
      params(
        filter_values: T::Array[String],
        field: MemexProjectColumn::Field::Iteration,
        negated: T::Boolean
      ).void
    end
    def initialize(filter_values, field:, negated: false)
      @start_date_resolver = T.let(
        MemexProject::FilterValueResolver.new(field, iteration_key: "start_date"),
        MemexProject::FilterValueResolver
      )
      @filter_values = T.let(filter_values.map { resolve_to_start_date(_1) }, T::Array[String])
      @negated = negated
    end

    # Convert any iteration titles, macros, ranges, etc. to their respective start dates,
    # and also apply any arithmetic offsets
    sig { params(filter_value: String).returns(String) }
    private def resolve_to_start_date(filter_value)
      return "" if filter_value.blank?

      if range_match = filter_value.match(ITERATION_RANGE_REGEX)
        start_iteration, range_operator, end_iteration = range_match.captures.map { strip_quotes(_1) }
        start_date, end_date = @start_date_resolver.resolve([T.must(start_iteration), T.must(end_iteration)])
        [start_date, range_operator, end_date].join

      elsif inequality_match = filter_value.match(ITERATION_INEQUALITY_REGEX)
        inequality_operator, iteration = inequality_match.captures.map { strip_quotes(_1) }
        date, _ = @start_date_resolver.resolve([T.must(iteration)])

        # Use `compact` to remove the inequality operator if it is nil
        [inequality_operator, date].compact.join

      else
        # This should be unreachable, because ITERATION_INEQUALITY_REGEX should match any non-empty string
        raise "Invalid iteration filter value: #{filter_value}"
      end
    end

    sig { params(iteration: T::Hash[String, T.untyped]).returns(T::Boolean) }
    def matches?(iteration)
      # Iterate through filter values individually so that we can consider an invalid date as non-matching.
      has_match = @filter_values.any? do |filter_value|
        begin
          MemexProject::DateComparator.new([filter_value]).matches?(iteration["start_date"])
        rescue Date::Error
          false
        end
      end
      has_match ^ @negated
    end

    # Strip surrounding quotes (either double or single quotes) from the given string
    sig { params(str: T.nilable(String)).returns(T.nilable(String)) }
    private def strip_quotes(str)
      return nil if str.nil?
      str.gsub(/\A['"]|['"]\z/, "")
    end
  end
end
