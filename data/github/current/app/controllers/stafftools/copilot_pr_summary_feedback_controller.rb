# typed: true
# frozen_string_literal: true

module Stafftools
  class CopilotPrSummaryFeedbackController < StafftoolsController
    extend T::Sig

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Billing,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::IssuesPullRequests,
      only: [:index, :show]

    before_action :dotcom_required # limiting to dotcom so only GitHub staff can access

    CSV_COLUMN_NAMES = [:user, :repository, :date, :summary, :sentiment, :detailed_feedback, :open_to_contact, :classification]
    FEEDBACK_RESULTS_PER_PAGE = 25

    def index
      type = params[:type] || "pr_summary"

      feedback = ::Copilot::CompletionFeedback
        .preload(:repository, :user)
        .order(id: :desc)
        .paginate(page: current_page, per_page: params[:per_page] || FEEDBACK_RESULTS_PER_PAGE)
        .all

      if params[:sentiment]
        feedback = feedback.where(sentiment: params[:sentiment])
      end

      if type == "text_completion"
        feedback = feedback.where.not(session_id: nil)
      elsif type == "pr_summary"
        feedback = feedback.where.not(job_id: nil)
      end

      respond_to do |format|
        format.html do
          render "stafftools/copilot_pr_summary_feedback/index", locals: { feedback:, type: }
        end
        format.csv do
          send_data CSV.generate { |csv|
            csv << CSV_COLUMN_NAMES
            feedback.each do |user_feedback|
              csv << [
                user_feedback.user.display_login,
                user_feedback.repository.name_with_display_owner,
                user_feedback.updated_at,
                user_feedback.context[:completion],
                user_feedback.sentiment,
                user_feedback.body,
                user_feedback.contact,
                user_feedback.classification
              ]
            end
          }, filename: "copilot-pr-summary-feedback.csv"
        end
      end
    end

    def show
      feedback = ::Copilot::CompletionFeedback
        .preload(:repository, :user)
        .find_by!(id: params[:feedback_id])

      # There might not be a PR if these shas have changed since the feedback was generated and we don't store a
      # pull request ID on the feedback because a user can generate a PR summary without first creating a PR
      pull_request = T.must(feedback.repository).pull_requests.find_by(
        base_sha: T.must(feedback).context[:base_oid],
        head_sha: T.must(feedback).context[:head_oid]
      )
      render "stafftools/copilot_pr_summary_feedback/show", locals: { feedback:, pull_request: }
    end
  end
end
