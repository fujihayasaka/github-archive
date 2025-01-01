# typed: true
# frozen_string_literal: true
module ActionsPrompt
  class PullRequestActionsTask < AbstractActionsTask
    NOTICE_KEY = "growth_pull_request_actions_prompt".freeze

    attr_reader :organization, :pull_request, :repository

    def initialize(pull_request)
      @pull_request = pull_request
      @repository = pull_request.repository
      @organization = repository&.organization
    end

    def repo_candidate?
      is_team_org? && supported_primary_language? && !has_actions_workflow?
    end

    private

    def task_ref
      @task_ref ||= pull_request.base_ref
    end

    def is_team_org?
      organization&.plan&.business?
    end
  end
end
