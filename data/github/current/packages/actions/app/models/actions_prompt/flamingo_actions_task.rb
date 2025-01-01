# typed: true
# frozen_string_literal: true

module ActionsPrompt
  class FlamingoActionsTask < AbstractActionsTask
    NOTICE_KEY = "growth_flamingo_pr_actions_prompt".freeze

    attr_reader :repository, :pull_request

    def initialize(pull_request)
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    def repo_candidate?
      !has_actions_workflow? && supported_primary_language?
    end

    private

    def task_ref
      @task_ref ||= pull_request.base_ref
    end
  end
end
