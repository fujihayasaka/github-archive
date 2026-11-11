# typed: true
# frozen_string_literal: true

# Used to clean and display backtraces for experiment results.
module Devtools::Experiments::BacktraceCleaning
  extend T::Helpers
  requires_ancestor { Devtools::Experiments::ExperimentData }

  # Public: the app-only backtrace for the experiment.
  #
  # This requires an experiment's context have the caller set explicitly, as
  # it's not recorded by default.
  #
  # Returns an Array of backtrace lines.
  def backtrace
    []
  end

  # Public: the raw experiment data.
  #
  # Mostly raw, anyway: the caller is explicitly excluded since it's rendered
  # separately.
  #
  # Returns a Hash of experiment data.
  def raw
    experiment_data.except "caller"
  end
end
