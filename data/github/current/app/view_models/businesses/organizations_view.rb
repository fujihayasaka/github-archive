# typed: true
# frozen_string_literal: true

class Businesses::OrganizationsView < Businesses::QueryView
  # Query filters defined for Businesses::QueryView
  attr_reader :viewer_role
  attr_reader :has_deploy_keys
  attr_reader :two_factor_policy

  def filter_map
    BusinessesHelper::ORGANIZATION_QUERY_FILTERS
  end
end
