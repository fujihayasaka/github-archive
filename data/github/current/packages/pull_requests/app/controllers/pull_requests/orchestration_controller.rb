# typed: true
# frozen_string_literal: true

class PullRequests::OrchestrationController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    optional: false, only: [:show]

  def show
    return head 404 unless pull_request = self.pull_request
    return head 404 unless orchestration = self.orchestration

    status = orchestration.active? ? 202 : 200
    result = {
      id: orchestration.id,
      state: orchestration.state,
      step_name: orchestration.step_name,
      attempts: orchestration.attempts,
      error_message: orchestration.error_message,
      current_head_sha: pull_request.head_sha,
    }
    render status: status, json: { orchestration: result }
  end

  private

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull_request
    PullRequest.with_number_and_repo(params[:id].to_i, current_repository)
  end

  sig { returns(T.nilable(PullRequestOrchestration)) }
  memoize def orchestration
    PullRequestOrchestration.find_by(pull_request_id: pull_request&.id, id: params[:orchestration_id])
  end
end
