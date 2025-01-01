# typed: true
# frozen_string_literal: true
require "monolith-twirp-education_web-repos"

module Api::Internal::Twirp::EducationWeb
  module Repos
    module V1
      # Handler for the MonolithTwirp::EducationWeb::Repos::V1::ClassroomReposAPIService
      class ClassroomReposAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["education_web"]
        handles_service MonolithTwirp::EducationWeb::Repos::V1::ClassroomReposAPIService
        connected_to_writing_for :get_classroom_repo_info

        def get_classroom_repo_info(req, env)
          assignment_repo_ids = req.classroom_assignment_github_ids.map(&:to_i)
          weeks_ago = req.weeks_ago.to_i
          from = weeks_ago.weeks.ago.to_s.to_date
          to = Date.tomorrow
          student_github_id = req.student_github_id.to_i
          user = User.find_by(id: student_github_id)
          accessor = Contribution::Accessor.new(
            user: user,
            viewer: user,
            contribution_classes: Contribution::Collector::CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS,
            date_range: from..to,
            organization_id: nil,
            skip_restricted: false,
            excluded_organization_ids: [],
            lightweight: false,
            )

          repository_contribution = accessor.visible_counts_by_repository_id
          repositories_contribution_count = []
          assignment_repo_ids.each do |assignment_repo_id|
            repositories_contribution_count << repository_contribution[assignment_repo_id]
          end
          { contribution_count: repositories_contribution_count.max }
        end
      end
    end
  end
end
