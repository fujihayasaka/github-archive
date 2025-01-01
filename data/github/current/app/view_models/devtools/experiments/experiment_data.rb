# typed: true
# frozen_string_literal: true

class Devtools::Experiments::ExperimentData < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  # A String-keyed Hash of mismatch data, probably decoded from JSON.
  attr_reader :experiment_data
end
