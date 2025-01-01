# typed: strict
# frozen_string_literal: true

class MemexProject
  # This Comparator class formats iteration ranges and returns the correct query for Elasticsearch.
  # This class understands the operators: >, >=, <, <=, and .. (inclusive range) when comparing strings like "Iteration 1".
  class IterationComparator
    extend T::Sig

    ITERATION_RANGE_REGEX = /
      (?<op>([><]=?|\.\.))?\s*   # Optional >, >=, <, <=, or .. operator at the start of the expression
      (?<start>[^.<>]+)?         # Non-greedy match for the start value, excluding '.', '<', '>', to avoid matching operators
      (?<range>\.\.              # Optional Range operator
        (?<end>[^.]+)?           # Greedy match for the end value, excluding '.' to avoid matching range operator again
      )?                         # The end value and range operator are optional
    /x

    sig do
      params(
        filter_values: T::Array[String],
        field: MemexProjectColumn::Iteration,
        negated: T::Boolean
      ).void
    end
    def initialize(filter_values, field:, negated: false)
      @resolver = T.let(
        MemexProject::FilterValueResolver.new(field, iteration_key: "start_date"),
        MemexProject::FilterValueResolver
      )
      @filter_values = T.let(sanitize_filter_values(filter_values), T::Array[String])
      @negated = negated
    end

    sig { params(filter_value: String).returns(String) }
    def resolve_to_start_date(filter_value)
      filter_value.gsub(ITERATION_RANGE_REGEX) do
        # $~ is a global variable that contains the last match data. It is the same as Regexp.last_match.
        captures = $~.named_captures.compact

        # Resolve the start and end values to their respective start dates
        iteration_start, iteration_end = @resolver.resolve([captures["start"], captures["end"]].compact)
        [
          captures["op"],
          iteration_start,
          (".." if captures["range"]),
          iteration_end
        ].compact.join
      end
    end

    sig { params(filter_values: T::Array[String]).returns(T::Array[String]) }
    def sanitize_filter_values(filter_values)
      filter_values.map do |filter_value|
        # The value may or may not contain double quotes, single quotes, and/or wildcard (*). If it does, discard them.
        sanitized_value = filter_value.tr("\"'*", "")
        # Convert any iteration titles, macros, ranges, etc. to their respective start dates (and apply any arithmetic offsets)
        resolve_to_start_date(sanitized_value)
      end
    end

    sig { params(iteration: T::Hash[String, T.untyped]).returns(T::Boolean) }
    def matches?(iteration)
      MemexProject::DateComparator.new(@filter_values).matches?(iteration["start_date"]) ^ @negated
    end
  end
end
