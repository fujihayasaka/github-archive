# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

module Actions
  class DeleteActionRequiredCheckSuiteJob < ApplicationJob
    queue_as :delete_action_required_check_suites

    retry_on_dirty_exit

    def perform(check_suite_id, repository_id, github_app_id)
      check_suite = CheckSuite.find_by(id: check_suite_id, repository_id: repository_id, github_app_id: github_app_id)

      if check_suite.blank? || check_suite.workflow_run.blank?
        result = "not_found"
      elsif !check_suite.action_required?
        result = "not_action_required"
      elsif !check_suite.workflow_run.deleteable?
        result = "not_deleteable"
      else
        begin
          with_write { check_suite.workflow_run.hard_delete(actor: User.staff_user) }
          result = "destroyed"
        rescue ActiveRecord::RecordNotDestroyed
          result = "destroy_failed"
        end
      end

      GitHub.dogstats.increment("actions.delete_action_required_check_suite_job", tags: ["result:#{result}"])
    end
  end
end
