# typed: true
# frozen_string_literal: true

class Devtools::Experiments::SampleView < Devtools::Experiments::ExperimentData
  include Devtools::Experiments::BacktraceCleaning

  def sample_threshold
    experiment_data["sample_threshold"]
  end

  def control_difference
    control_duration - sample_threshold
  end

  def control_duration
    experiment_data["control"]["duration"]
  end

  def candidate_durations
    experiment_data["execution_order"].map do |name|
      next if name == "control"
      duration = experiment_data[name]["duration"]
      difference = duration - sample_threshold
      [name, duration, difference]
    end.compact
  end

  def platform_type_name
    "ExperimentSample"
  end
end
