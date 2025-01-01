# typed: true
# frozen_string_literal: true

class Businesses::OutsideCollaboratorsView < Businesses::QueryView
  # query filters defined for QueryView
  attr_reader :visibility, :two_factor_status, :organizations

  def filter_map
    BusinessesHelper::OUTSIDE_COLLABS_QUERY_FILTERS
  end

  def outside_collaborator_link_data_options(collaborator)
    return {} unless collaborator

    helpers.hovercard_data_attributes_for_user(collaborator)
  end
end
