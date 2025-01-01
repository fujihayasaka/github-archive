# typed: true
# frozen_string_literal: true

class Copilot::SeatManagement::TeamSuggestionsComponent < ApplicationComponent
  DEFAULT_SUGGESTIONS = 15

  def initialize(organization:, query:, added_teams: [], limit: DEFAULT_SUGGESTIONS)
    @org = organization
    @query = query
    @limit = limit
    @added_teams = added_teams
  end

  memoize def teams
    if @query.blank?
      return []
    end

    scope = selectable_teams

    exact_match = scope.where("teams.name" => @query).first

    scope = scope.where("teams.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    scope = scope.order(:name).limit(@limit)
    scope = scope.where.not(id: @added_teams)

    scope.to_a.prepend(exact_match).uniq.compact.first(@limit)
  end

  private

  def selectable_teams
    @org.teams
  end
end
