# typed: strict
# frozen_string_literal: true

# Open up Scientist and hack it to return our own GitHub Experiment.
#
# See GitHub::Experiment
module Scientist::Experiment
  sig { params(name: String).returns(GitHub::Experiment) }
  def self.new(name)
    GitHub::Experiment.new(name)
  end
end

ActiveSupport.on_load(:action_controller) do
  class ActionController::Base
    include Scientist
  end
end

ActiveSupport.on_load(:active_record) do
  class ActiveRecord::Base
    include Scientist
    extend Scientist
  end
end

if Rails.env.test?
  GitHub::Experiment.raise_on_mismatches = true
  GitHub::Experiment.raise_on_internal_errors = true
elsif Rails.env.development?
  GitHub::Experiment.raise_on_mismatches = false
  GitHub::Experiment.raise_on_internal_errors = true
end
