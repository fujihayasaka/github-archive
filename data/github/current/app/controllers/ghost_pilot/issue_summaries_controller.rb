# typed: true
# frozen_string_literal: true

module GhostPilot
  class IssueSummariesController < ApplicationController
    include RepositoryControllerMethods
    include ApplicationController::VerifiedFetchDependency

    allow_verified_fetch only: [:show]

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
      render_404 and return unless current_repository

      issue_number = params[:id].to_i
      issue = current_repository.issues.find_by_number(issue_number)

      render_404 and return unless issue

      render json: {
        number: issue.number,
        title: issue.title,
        body: issue.body
      }
    end
  end
end
