# typed: true
# frozen_string_literal: true

class Checks::ChecksToolbarView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  class StatusCheck
    attr_accessor :state

    def initialize(state)
      @state = state
    end
  end

  attr_reader :pull
  attr_reader :commit
  attr_reader :selected_check_suite
  attr_reader :check_suites
  attr_reader :selected_check_run
  attr_reader :commit_check_runs

  def check_suite
    selected_check_run&.check_suite || selected_check_suite
  end

  def commit_check_runs_with_state
    return @commit_check_runs_with_state if @commit_check_runs_with_state

    latest_check_runs = commit_check_runs.group_by(&:name).values.map { |arr| arr.max_by(&:id) }
    @commit_check_runs_with_state = latest_check_runs.map do |c|
      [c.name, (c.conclusion || c.status).upcase]
    end
    # If there's any check suite with an explicit completion and is not completed, create a dummy queued state to
    # prevent showing the icon that would indicate a completed state
    if check_suites.any? { |check_suite| check_suite.explicit_completion && !check_suite.completed? }
      @commit_check_runs_with_state.push ["", "QUEUED"]
    end
    # If there's any check suite completed without check runs, we use it's conclusion
    check_suites.filter { |check_suite| check_suite.completed? && check_suite.check_runs.where(repository_id: check_suite.repository_id).empty? }.each do |check_suite|
      @commit_check_runs_with_state.push ["", check_suite.conclusion.upcase]
    end

    @commit_check_runs_with_state
  end

  def contexts_helper
    Statuses::ContextsHelper.new(commit_check_runs_with_state)
  end

  def rollup_state
    @status_check_rollup ||= StatusCheckRollup.new(status_checks: commit_check_runs_with_state.map { |arr| StatusCheck.new(arr[1].downcase) })
    @status_check_rollup.state
  end

  def branches
    check_suites.map(&:head_branch).compact.uniq
  end
end
