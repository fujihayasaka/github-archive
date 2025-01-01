# typed: true
# frozen_string_literal: true

class GitHub::LaunchClient::RunnerGroupResponse
  attr_reader :runner_group

  def initialize(runner_group)
    @runner_group = runner_group
  end
end
