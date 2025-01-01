# typed: true
# frozen_string_literal: true

class SuggestedReviewersController < AbstractRepositoryController

  before_action :login_required
  before_action :ensure_current_pull_request

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    respond_to do |format|
      format.html do
        render partial: "pull_requests/suggested_reviewers", locals: {
          pull_request: current_pull_request,
          suggestions: current_pull_request.suggested_reviewers,
        }
      end
    end
  end

  private

  # This controller is routed to two paths: one with a `:range` parameter
  # and another with `:id` for existing pull requests.
  #
  # The range allows us to suggest reviewers based only on the base and head
  # refs during pull request creation.
  #
  # The id allows us to suggest reviewers on an existing pull request and
  # exclude the pull request author. The author cannot merge until someone
  # else provides an approved review so don't suggest the author as a reviewer.
  #
  # Returns a PullRequest or nil if prevented by authorization checks.
  memoize def current_pull_request
    if params[:id]
      current_repository.issues.where(number: params[:id]).first.try(:pull_request)
    elsif params[:range]
      comparison = GitHub::Comparison.from_range_or_ref(
        current_repository,
        Addressable::URI.unescape(params[:range]),
        user: current_user,
      )
      if comparison.valid? && comparison.viewable_by?(current_user)
        comparison.build_pull_request(user: current_user).tap do |pull|
          pull.build_issue(repository: pull.repository)
        end
      end
    end
  end

  def ensure_current_pull_request
    render_404 unless current_pull_request
  end

  def route_supports_advisory_workspaces?
    true
  end
end
