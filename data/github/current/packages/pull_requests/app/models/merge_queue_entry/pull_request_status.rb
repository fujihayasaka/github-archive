# typed: true
# frozen_string_literal: true

# Private to the MergeQueueEntry class, to validate queue entry status based on the given PullRequest.
class MergeQueueEntry
  class PullRequestStatus
    attr_reader :pull_request

    def initialize(pull_request)
      @pull_request = pull_request
    end

    def required_status_success?
      status_check_rollup_state == StatusCheckConfig::SUCCESS
    end

    def required_status_failing?
      status_check_rollup_state == StatusCheckConfig::FAILURE
    end

    private

    def status_check_rollup_state
      return StatusCheckConfig::SUCCESS unless base_branch_rule_evaluator
      return StatusCheckConfig::SUCCESS if pull_request.combined_status.green?
      return StatusCheckConfig::SUCCESS if required_status_checks.empty?

      @status_check_rollup_state ||= StatusCheckRollup
        .new(status_checks: required_status_checks)
        .state
    end

    def required_status_checks
      @required_status_checks ||= if base_branch_rule_evaluator
        required_contexts = Set.new(base_branch_rule_evaluator.required_status_checks.pluck(:context))
        if required_contexts.empty?
          []
        else
          pull_request.combined_status.status_checks.filter { |s| required_contexts.include?(s.context) }
        end
      else
        []
      end
    end

    def base_branch_rule_evaluator
      return @base_branch_rule_evaluator if defined?(@base_branch_rule_evaluator)
      @base_branch_rule_evaluator = pull_request.base_branch_rule_evaluator
    end
  end
end
