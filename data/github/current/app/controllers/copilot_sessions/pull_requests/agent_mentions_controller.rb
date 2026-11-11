# typed: true
# frozen_string_literal: true

module CopilotSessions
  module PullRequests
    class AgentMentionsController < ApplicationController
      before_action :login_required
      before_action :only_xhr_request
      before_action :load_pull_request

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql2,
        ApplicationRecord::IssuesPullRequests,
        ApplicationRecord::Repositories,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::SecurityProductsEnablement,
        ApplicationRecord::Configurations,

      # GET /copilot/agent-sessions/pull-requests/:pull_request_id/agent-mentions
      # Fetch a list of AgentMention records for the specified event types for a
      # given pull request. If no events are specified in query params, return
      # an empty list.
      def index
        render_404 unless @pull.repository.readable_by?(@current_user)

        # Return empty list if no events specified
        if pull_request_comment_ids.blank? && pull_request_review_ids.blank?
          return render json: {
            pull_request_id: @pull.id,
            agent_mentions: []
          }
        end

        loader = CopilotSessions::AgentMentionsLoader.new(
          pull_request: @pull,
          comment_ids: pull_request_comment_ids,
          review_ids: pull_request_review_ids
        )

        render json: {
          pull_request_id: @pull.id,
          agent_mentions: loader.load_all
        }
      end

      private

      def load_pull_request
        pull_id = params[:pull_request_id]
        @pull = PullRequest.includes(:repository, :issue, :user).find(pull_id)

        render_404 if repo_hidden_from_user?
      end

      def pull_request_review_ids
        params[:pull_request_review_ids] || []
      end

      def pull_request_comment_ids
        params[:pull_request_comment_ids] || []
      end

      def repo_hidden_from_user?
        @pull.hide_from_user?(@current_user) || !@pull.repository.readable_by?(@current_user)
      end

      def only_xhr_request
        render_404 unless request.xhr?
      end

      def target_for_conditional_access
        current_user
      end
    end
  end
end
