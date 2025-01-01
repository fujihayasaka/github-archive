# typed: true
# frozen_string_literal: true
class Memex::ProjectList::HeaderComponent < ApplicationComponent
  extend T::Sig

  include MemexesHelper

  sig do
    params(
      open_memex_count: Integer,
      closed_memex_count: Integer,
      parsed_query: Search::Queries::MemexProjectQuery,
      open_projects_path: String,
      closed_projects_path: String,
      projects_path: String,
    ).void
  end
  def initialize(open_memex_count:, closed_memex_count:, parsed_query:, open_projects_path:, closed_projects_path:, projects_path:)
    @open_memex_count = open_memex_count
    @closed_memex_count = closed_memex_count
    @parsed_query = parsed_query
    @open_projects_path = open_projects_path
    @closed_projects_path = closed_projects_path
    @projects_path = projects_path
  end

  sig { returns(Symbol) }
  def open_icon
    @parsed_query.state_filters.include?("template") ? :"project-template" : :table
  end

  sig { returns(T::Boolean) }
  def closed_state?
    @parsed_query.state_filters.include?("closed") && @parsed_query.state_filters.exclude?("open")
  end

  sig { returns(T::Boolean) }
  def open_state?
    @parsed_query.state_filters.include?("open") && @parsed_query.state_filters.exclude?("closed")
  end
end
