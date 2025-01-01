# typed: true
# frozen_string_literal: true

module GhostPilot
  class RecentInteractionsController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::NotificationsEntries,
      only: [:index]

    def index
      render_404 and return unless request.xhr?
      unauthorized_account_ids = cap_filter.unauthorized_resource_ids(current_user&.resources_for_cap_filter)

      recent_interactions = Issue::RecentInteractions.new(
        current_user,
        types: [:issue, :pull_request],
        since: 1.day.ago,
        organization_id: params[:organization_id],
        excluded_account_ids: unauthorized_account_ids,
      ).fetch(limit: 10)

      render GhostPilot::RecentInteractionsComponent.new(recent_interactions: recent_interactions), layout: false
    end

    private

    def target_for_conditional_access
      if params[:organization_id]
        organization
      else
        current_user
      end
    end

    def organization
      return unless params[:organization_id]

      Organization.find_by(id: params[:organization_id])
    end
  end
end
