# typed: true
# frozen_string_literal: true

require "pp"

class Devtools::Experiments::MismatchView < Devtools::Experiments::ExperimentData
  include Devtools::Experiments::BacktraceCleaning

  # We truncate control/candidate values that are longer than this to avoid
  # making the page really big.
  MAXIMUM_VALUE_STRING_LENGTH = 1024

  # Internal: the context values reported with this mismatch
  #
  # Returns a Hash of context names and values
  def context
    experiment_data.without("control", "candidate")
  end

  # Internal: the candidate values for this experiment.
  #
  # Returns an Array of candidate names, candidate values, and the exception
  # class raised if applicable.
  def candidate_values
    candidates = experiment_data["execution_order"] - ["control"]
    candidates.sort.map do |name|
      [name, experiment_data[name]["value"], exception_for(name)]
    end
  end

  # Internal: the control value for this experiment
  def control_value
    experiment_data["control"]["value"]
  end

  # Internal: an inspect-able version of an exception that a candidate raised
  def exception_for(name)
    if exception = experiment_data[name]["exception"]
      "#{exception["class"]}: #{exception["message"]}"
    else
      nil
    end
  end

  # Public: The control value, truncated for display, and exception if raised.
  #
  # Returns an Array containing [truncated_string, is_truncated, exception].
  def control_value_with_truncation
    string, truncated = truncated_value(control_value)
    [string, truncated, exception_for("control")]
  end

  # Public: the candidate values, potentially truncated for display
  #
  # Returns an Array of [candidate_name, value, is_truncated, exception]
  def candidate_values_with_truncation
    candidate_values.map do |name, value, exception|
      string, truncated = truncated_value(value)
      [name, string, truncated, exception]
    end
  end

  # Public: diffs per candidate
  #
  # Returns an Array of [candidate_name, highlighted_diff].
  def diff_lines_by_candidate
    control = pretty_print_for_diff(control_value)
    candidate_values.map do |name, value, exception|
      next if exception
      candidate = pretty_print_for_diff(value)
      diff = GitHub::Diff::Generator.diff(experiment_data["name"], control, candidate)
      diff = GitHub::Colorize.highlight_one("source.diff", diff)
      [name, diff]
    end.compact
  end

  # Public: Raw experiment data as syntax-highlighted YAML
  #
  # Returns an Array of highlighted HTML strings.
  def raw_data_lines
    GitHub::Colorize.highlight_one("source.yaml", raw.to_yaml)
  end

  def platform_type_name
    "ExperimentMismatch"
  end

  private

  # Internal: truncate a string if it's too long.
  #
  # Returns an pair of the potentially truncated string and a boolean whether it
  # was truncated or not.
  def truncated_value(value)
    string = value.inspect
    truncated = string.size > MAXIMUM_VALUE_STRING_LENGTH
    string = string[0, MAXIMUM_VALUE_STRING_LENGTH]
    string << "..." if truncated
    [string, truncated]
  end

  # Based on https://github.com/seattlerb/minitest/blob/1c3ac56179bfc972cf06b9333e1f3a3bb7ec3974/lib/minitest/assertions.rb#L111-L119
  def pretty_print_for_diff(value)
    return value if value.is_a?(String)
    value.pretty_inspect.gsub(/\\n/, "\n").gsub(/:0x[a-fA-F0-9]{4,}/m, ":0xXXXXXX")
  end
end
