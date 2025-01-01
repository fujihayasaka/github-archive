# typed: true
# frozen_string_literal: true

class Memex::ProjectList::Blankslate::BlankslateOrgUserComponent < ApplicationComponent
  extend T::Sig

  attr_reader :label, :icon, :is_org

  sig { returns(T.nilable(MemexStats::UIValues)) }
  attr_reader :ui

  def initialize(has_no_projects:, member_or_current_user:, parsed_query:, is_org_empty:, is_user_empty:, owner:)
    @has_no_projects = has_no_projects
    @member_or_current_user = member_or_current_user
    @parsed_query = parsed_query
    @is_org_empty = is_org_empty
    @is_user_empty = is_user_empty
    @owner = owner
    @is_org = owner.is_a?(Organization)
    @label = @is_org && parsed_query.has_template_filter? ? "project template" : "project"
    @icon = @is_org && parsed_query.has_template_filter? ? "project-template" : :table
    @ui = @is_org ? MemexStats::UIValues::OrgIndex : MemexStats::UIValues::UserIndex
  end

  memoize def has_template_filter?
    @is_org && @parsed_query.has_template_filter?
  end
end
