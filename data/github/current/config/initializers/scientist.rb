# typed: strict
# frozen_string_literal: true

# Type checking is ignored in this file because Sorbet is confused by the `module_eval` below.
# Once we have upgraded Scientist to a newer version that supports Scientist::Experiment.set_default
# We can re-enable type checking and remove this module_eval.

# Open up Scientist and hack it to return our own GitHub Experiment.
#
# See GitHub::Experiment
module Scientist::Experiment
  sig { params(name: String).returns(GitHub::Experiment) }
  def self.new(name)
    GitHub::Experiment.new(name)
  end
end

class ActionController::Base
  include Scientist
end

class ActiveRecord::Base
  include Scientist
  extend Scientist
end

if Rails.env.test?
  GitHub::Experiment.raise_on_mismatches = true
  GitHub::Experiment.raise_on_internal_errors = true
elsif Rails.env.development?
  GitHub::Experiment.raise_on_mismatches = false
  GitHub::Experiment.raise_on_internal_errors = true
end
