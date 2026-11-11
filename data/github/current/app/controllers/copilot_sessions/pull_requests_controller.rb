# typed: true
# frozen_string_literal: true

class CopilotSessions::PullRequestsController < ApplicationController
  include Commit::ReactPayloadDataDependency

  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::SecurityProductsEnablement,
    ApplicationRecord::Configurations,

  def index
    return render_404 unless request.xhr?
    pull_request_ids = params["pull_request_ids"] || []

    pr_map = CopilotSessions::Public.id_to_pull_request_map(pull_request_ids:
      pull_request_ids.split(",").map(&:to_i), user: current_user, cap_filter: cap_filter)

    if params["include_body"] == "true"
      pr_map = add_body_to_pull_requests(pr_map)
    end

    render json: { pull_requests: pr_map }
  end

  private

  def target_for_conditional_access
    current_user
  end

  def add_body_to_pull_requests(pr_map)
    # Add body data to each pull request when explicitly requested
    pull_request_ids = pr_map.keys
    pull_requests = PullRequest.includes(:repository).where(id: pull_request_ids).index_by(&:id)
    pr_map.transform_values do |pr_data|
      pull_request = pull_requests[pr_data.id]
      if pull_request
        pr_data.with(body: pull_request.body, body_html: pull_request.body_html)
      else
        pr_data
      end
    end
  end
end
