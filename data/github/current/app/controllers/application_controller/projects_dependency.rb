# typed: false
# frozen_string_literal: true

module ApplicationController::ProjectsDependency
  # Track edits made to issues and pull requests directly from a project board
  def track_issue_edits_from_project_board(edited_fields: [])
    referring_route = github_internal_referrer_route
    return unless referring_route.present?

    from_controller = referring_route[:controller]
    return unless %W(repos/projects orgs/projects users/projects).include?(from_controller)

    tags = edited_fields.map { |field| "field:#{field}" }

    controller_tag = case from_controller
    when "repos/projects"
      "owner:repository"
    when "orgs/projects"
      "owner:organization"
    when "users/projects"
      "owner:user"
    end

    tags << controller_tag
    GitHub.dogstats.increment("projects.issue_edits", tags: tags)
  end
end
