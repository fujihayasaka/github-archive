# typed: strict
# frozen_string_literal: true

# Shared task-creation logic for "Fix with Copilot" actions across code review
# controllers. Both the findings fix endpoint and the apply-changes-button
# endpoint use this to create coding agent tasks with consistent parameters.
module Copilot::CodeReviewFixConcern
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { AbstractRepositoryController }

  private

  sig do
    params(
      pull_request: PullRequest,
      problem_statement: String,
      create_pull_request: T::Boolean,
      entry_point: Symbol,
      event_type: String,
      model: T.nilable(String),
    ).returns(CopilotSessions::TaskApi::Task)
  end
  def create_code_review_fix_task(pull_request, problem_statement:, create_pull_request:, entry_point:, event_type:, model: nil)
    user = current_user
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: user,
      entry_point: entry_point,
      user_session: user_session,
    )

    base_ref = create_pull_request ? pull_request.head_ref : pull_request.base_ref
    head_ref = create_pull_request ? nil : pull_request.head_ref

    CopilotSessions::TaskApi::Task.create(
      repository: current_repository,
      user: user,
      token: token,
      base_ref: base_ref,
      head_ref: head_ref,
      create_pull_request: create_pull_request,
      entry_point: entry_point,
      event_type: event_type,
      model: model,
      problem_statement: problem_statement,
    )
  end

  sig { void }
  def code_review_access_required
    return true if Rails.env.development?
    access = PullRequests::Copilot::CodeReviewAccess.new(actor: current_user, current_repository: current_repository, bypass_quota_check: true)
    render_404 unless access.can_create_review_request?
  end

  sig { void }
  def require_copilot_swe_agent_enabled
    return true if Rails.env.development?
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user)
  end
end
