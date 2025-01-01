# typed: true
# frozen_string_literal: true

class Businesses::OrganizationsView < Businesses::QueryView
  # Query filters defined for Businesses::QueryView
  attr_reader :viewer_role

  def filter_map
    BusinessesHelper::ORGANIZATION_QUERY_FILTERS
  end
end
