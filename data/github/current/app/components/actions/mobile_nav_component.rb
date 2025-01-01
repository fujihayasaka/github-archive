# typed: true
# frozen_string_literal: true

class Actions::MobileNavComponent < ApplicationComponent

  def initialize(
    selected_workflow:,
    selected_section:,
    current_repo:,
    workflow_run_filters:)
    @selected_workflow = selected_workflow
    @selected_section = selected_section || :all_workflows
    @current_repository = current_repo
    @workflow_run_filters = workflow_run_filters
  end

  def nav_content_src
    query = Search::ParsedQuery.stringify(@workflow_run_filters)
    actions_navigation_partial_path(
      user_id: @current_repository.owner,
      repository: @current_repository,
      query: query,
      workflow_file_name: @selected_workflow&.filename,
      selected_section: @selected_section,
      lab: @selected_workflow&.lab?,
    )
  end

  def overlay_button_text
    @selected_workflow&.name || @selected_section.to_s.humanize
  end
end
