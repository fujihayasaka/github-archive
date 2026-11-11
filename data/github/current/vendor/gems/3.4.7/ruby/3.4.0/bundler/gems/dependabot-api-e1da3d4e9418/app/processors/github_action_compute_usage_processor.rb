# frozen_string_literal: true

class GitHubActionComputeUsageProcessor < ApplicationProcessor
  group_name "actions_compute_usage"
  handle_topic(/github\.actions\.v0\.ComputeUsage\Z/, GitHubActionComputeUsageHandler)

  def initialize
    options[:session_timeout] = 15.minutes
  end
end
