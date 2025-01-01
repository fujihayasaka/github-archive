# typed: true
# frozen_string_literal: true

class Repos::Dependabot::Autofix::FeedbackController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::PartialRenderWithLayoutDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::Dependabot::Autofix::FeedbackController#create",
  ]

  before_action :login_required
  before_action :writable_repository_required, only: [:create]
  before_action :content_authorization_required, only: [:create]
  skip_before_action :cap_pagination

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities, only: [:create]

  def create
    pull = PullRequest.with_number_and_repo(params[:pull_id].to_i, current_repository)

    return head :not_found unless pull

    payload = {
      repository_id: current_repository.id,
      autofix_job_id: params[:autofix_job_id].to_i,
      user_analytics_tracking_id: current_user.analytics_tracking_id,
      pull_request_id: pull.id,
      pull_request_number: pull.number,
      type: params[:feedback],
    }

    if params[:feedback_choice].present?
      # validate feedback choices
      params[:feedback_choice].each do |choice|
        unless Dependabot::Autofix::FEEDBACK_OPTIONS.include?(choice.to_sym)
          head :bad_request
          return
        end
      end
      payload.merge!(choice: params[:feedback_choice])
    end

    if params[:text_response].present?
      unless params[:text_response].is_a?(String)
        head :bad_request
        return
      end
      payload.merge!(text_response: params[:text_response])
    end

    GlobalInstrumenter.instrument("dependabot.autofix_feedback", payload)

    head :ok
  end

  private

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository, action_to_authorize: :apply_suggestions)
  end
end
