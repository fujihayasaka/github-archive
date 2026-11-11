# typed: strict
# frozen_string_literal: true

# Custom experiment for Licensify that builds off the GitHub::Experiment class
module GitHub
  module Licensing
    module Licensify
      class Experiment < GitHub::Experiment
      end
    end
  end
end

# Licensify does not currently fake data in development/testing environments
# and fails any test running the experiment. This is a temporary workaround
# to allow the experiments to pass tests.
if Rails.env.test? || Rails.env.development? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
  GitHub::Licensing::Licensify::Experiment.raise_on_mismatches = false
  GitHub::Licensing::Licensify::Experiment.raise_on_internal_errors = true
end
