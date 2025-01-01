# typed: true
# frozen_string_literal: true

module Actions
  class PullRequestWorkflowApprovalComponent < ApplicationComponent
    def initialize(pull_request:, check_suites:, checks_status_summary: nil)
      @pull_request = pull_request
      @check_suites = check_suites
      @checks_status_summary = checks_status_summary
    end

    def show_run_workflows_button?
      @pull_request.repository.writable_by?(current_user) && !has_all_expired_workflow_runs?
    end

    def has_expired_workflow_runs?
      @check_suites.select(&:expired_workflow_run?).any?
    end

    def has_all_expired_workflow_runs?
      @check_suites.all?(&:expired_workflow_run?)
    end

    memoize def private_approval?
      @pull_request.repository.private?
    end

    def approval_message
      if private_approval?
        "Users without write permissions need approval to run workflows."
      else
        "This workflow requires approval from a maintainer."
      end
    end

    def help_link
      if private_approval?
        "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks"
      else
        "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-public-forks"
      end
    end

    def run_workflows_path
      pull_request_run_action_required_workflows_path(
        id: @pull_request.number,
        repository: @pull_request.repository,
        user_id: @pull_request.repository.owner.display_login,
      )
    end
  end
end
