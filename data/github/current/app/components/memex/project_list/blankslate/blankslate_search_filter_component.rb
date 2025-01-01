# typed: true
# frozen_string_literal: true

class Memex::ProjectList::Blankslate::BlankslateSearchFilterComponent < ApplicationComponent
  attr_reader :label, :icon

  def initialize(member_or_current_user:, parsed_query:, org_project: false)
    @member_or_current_user = member_or_current_user
    @parsed_query = parsed_query
    @label = org_project && parsed_query.has_template_filter? ? "project template" : "project"
    @icon = org_project && parsed_query.has_template_filter? ? :"project-template" : :table
  end
end
