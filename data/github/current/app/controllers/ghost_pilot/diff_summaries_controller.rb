# typed: true
# frozen_string_literal: true

module GhostPilot
  class DiffSummariesController < ApplicationController
    include RepositoryControllerMethods

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::Copilot,
      ApplicationRecord::Spokes,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::NotificationsEntries,
      only: [:show]

    def show
      render_404 and return unless request.xhr?
      render_404 and return unless current_user
      render_404 and return unless current_repository

      comparison = GitHub::Comparison.from_range_or_ref(current_repository, params[:range], user: current_user)
      render_404 and return unless comparison&.viewable_by?(current_user)

      render GhostPilot::DiffSummaryComponent.new(comparison: comparison), layout: false
    end
  end
end
