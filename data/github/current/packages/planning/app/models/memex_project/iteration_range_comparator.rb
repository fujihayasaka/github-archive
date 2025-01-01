# typed: strict
# frozen_string_literal: true

class MemexProject
  # This Comparator class formats iteration ranges and returns the correct query for Elasticsearch.
  # This class understands the operators: >, >=, <, <=, and .. (inclusive range) when comparing strings like "Iteration 1".
  class IterationRangeComparator < Comparator
    extend T::Sig

    # Defines all the regular expressions that can match against the filter value. Captures are named to be passed
    # directly to a range clause in elasticsearch.
    REGEX_OPERATOR = T.let([
      # Range query, inclusive. For example: "Iteration 1..Iteration 2"
      /(?<gte>.*)\.\.(?<lte>.*)/,
      # Greater than or equal to. For example: ">=Iteration 1"
      />=(?<gte>.*)/,
      # Greater than or equal to, using range syntax. For example: "Iteration 1..*"
      /(?<gte>.*)\.\.\*/,
      # Less than or equal to. For example: "<=Iteration 1"
      /<=(?<lte>.*)/,
      # Less than or equal to, using range syntax. For example: "*..Iteration 1"
      /\*\.\.(?<lte>.*)/,
      # Greater than. For example: ">Iteration 1"
      />(?<gt>.*)/,
      # Less than. For example: "<Iteration 1"
      /<(?<lt>.*)/,
    ].freeze, T::Array[Regexp])

    # main method for getting the correct query for Elasticsearch
    # converts [{:gte=>"Iteration 1", :lte=>"Iteration 2"}] to {:gte=>"2023-11-27", :lte=>"2023-12-04"}
    #
    # it takes the iterations from the column to convert string to date.
    #
    # iterations:
    # "iterations"=>[
    # {"id"=>"16fb5498", "title"=>"Iteration 1", "duration"=>7, "start_date"=>"2023-11-27", "title_html"=>"Iteration 1"},
    # {"id"=>"2ca18298", "title"=>"Iteration 2", "duration"=>7, "start_date"=>"2023-12-04", "title_html"=>"Iteration 2"}]
    sig { params(iterations: T::Array[T::Hash[String, String]], patterns: T::Hash[Symbol, String]).returns(T.nilable(T::Hash[Symbol, String])) }
    def range_clause(iterations, patterns)
      range_clause = {}
      patterns.each do |key, value|
        iterations.each do |iteration|
          if iteration["title"] == value
            range_clause.merge!(key => iteration["start_date"])
            break
          end
        end
      end

      range_clause.presence
    end

    sig { params(filter_values: T::Array[String]).returns(T::Array[String]) }
    private def sanitize_filter_values(filter_values)
      filter_values.map do |value|
        # Input may or may not contain double quotes, single quotes, and/or wildcard (*).
        # If it does, discard them.
        value
          .to_s
          .tr('"', "")
          .tr("'", "")
          .tr("*", "")
      end
    end

    # Public: main method for getting the correct regex format
    #
    # when filtering strings like "Iteration 1..Iteration 2" this method will return {:gte=>"Iteration 1", :lte=>"Iteration 2"}
    sig { returns(T::Hash[Symbol, String]) }
    def range_patterns
      return {} unless filter_values.any?
      filter_value = T.cast(filter_values.first, String)

      REGEX_OPERATOR.each do |pattern|
        match = filter_value.match(pattern)
        return match.named_captures.symbolize_keys if match.present?
      end

      {}
    end
  end
end
