# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Tabs
      module ActivityOverview
        class TeamsComponent < ApplicationComponent
          TEAMS_TO_SHOW = 3

          def initialize(teams:, scoped_organization_id:)
            @teams = teams
            @scoped_organization_id = scoped_organization_id
          end

          def render?
            visible_teams.any?
          end

          private

          attr_reader :teams, :scoped_organization_id

          delegate :activity_overview_link_hydro_attrs, to: :helpers

          memoize def teams_count
            teams.size
          end

          memoize def visible_teams_count
            visible_teams.size
          end

          memoize def visible_teams
            teams.first(TEAMS_TO_SHOW)
          end

          memoize def remaining_count
            teams_count - visible_teams_count
          end
        end
      end
    end
  end
end
