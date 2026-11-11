# typed: true
# frozen_string_literal: true

class Memex::ProjectList::Blankslate::BlankslateLinkerComponent < ApplicationComponent
  attr_reader :label, :org_project

  def initialize(parsed_query:, current_user_can_push:, team_member:, org_project:)
    @parsed_query = parsed_query
    @current_user_can_push = current_user_can_push
    @team_member = team_member
    @org_project = org_project
    @label = org_project && parsed_query.has_template_filter? ? "project templates" : "projects"
  end

  memoize def icon
    return "project-template" if @parsed_query.has_template_filter?
    "table"
  end

  def default_open_filter?
    @parsed_query.default_open_filter?(strip_template_filter: @org_project)
  end

  def default_closed_filter?
    @parsed_query.default_closed_filter?(strip_template_filter: @org_project)
  end
end
