# typed: true
# frozen_string_literal: true

class ReviewThreadSyntaxHighlightedDiffLinesController < GitContentController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    optional: true, only: [:index]

  def index
    return render_404 if no_pull_request?

    render json: SyntaxHighlightedDiffLineBatch.new(
      current_pull_request.id,
      pull_request_review_thread_ids,
    )
  rescue ActionController::ParameterMissing
    render json: { error: "Invalid payload" }, status: :unprocessable_entity
  end

  private

  def no_pull_request?
    current_pull_request.nil? || current_pull_request.hide_from_user?(current_user)
  end

  memoize def current_pull_request
    PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)
  end

  def pull_request_review_thread_ids
    inputs = params.require(:items).permit!.to_h
    inputs.transform_values { |item| item["pull_request_review_thread_id"].to_i }
  end
end
