# typed: false
# frozen_string_literal: true

module Profiles
  module ContributionGraphDependency
    extend ActiveSupport::Concern

    private

    included do
      helper_method :non_graphql_calendar_collector
      helper_method :organization_selector_collector
      helper_method :team_count
    end

    def non_graphql_calendar_collector
      @_non_graphql_calendar_collector ||= begin
        Contribution::Collector.new(
          user: this_user,
          viewer: current_user,
          time_range: yearly_collector_time_range || Contribution::Calendar.time_range_ending_on(Time.current),
          organization_id: scoped_organization&.id,
          excluded_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations),
          lightweight: true,
        )
      end
    end

    # Exactly the same as activity_collector but does not scope to the `scoped_organization`
    # This is used to populate the organization buttons
    def organization_selector_collector
      @_organization_selector_collector ||= begin
        if scoped_organization
          Contribution::Collector.new(
            user: this_user,
            viewer: current_user,
            time_range: yearly_collector_time_range || Contribution::Calendar.time_range_ending_on(Time.current),
            organization_id: nil,
            excluded_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations),
            lightweight: true,
          )
        else
          # When we're not scoping by an org, we can re-use the
          # calendar collector to determine organizations contributed to.
          non_graphql_calendar_collector
        end
      end
    end

    def team_count
      return 0 unless show_teams?

      @_team_count ||= this_user.async_visible_teams_for(current_user).then do |scope|
        scope = ::Team.ranked_for(this_user, scope: scope)

        scope = if scoped_organization&.id
          scope.owned_by(scoped_organization)
        else
          scope
        end

        scope.count
      end.sync
    end

    def yearly_collector_time_range
      base_from_date = params[:from].present? && parse_date_from(params[:from])
      base_to_date = params[:to].present? && parse_date_from(params[:to])
      base_date = base_to_date || base_from_date

      if base_date
        # If a user has specified a date range that isn't in the current year,
        # log the year/age to inform data retention needs.
        #
        # Feature-flagged in case logging is causing problems.
        if FeatureFlag.vexi.enabled?(:log_contribution_graph_age, default: false)
          age = Time.current.year - base_date.year
          GitHub.logger.info(
            "code.namespace" => "Profiles::ContributionGraphDependency",
            "code.function" => "yearly_collector_time_range",
            "gh.contributions.year" => base_date.year,
            "gh.contributions.age" => age,
          ) if age != 0
        end

        from = base_date.beginning_of_year
        to = base_date.end_of_year

        from..to
      end
    end
  end
end
