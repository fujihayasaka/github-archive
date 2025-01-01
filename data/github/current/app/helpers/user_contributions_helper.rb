# typed: true
# frozen_string_literal: true

module UserContributionsHelper
  extend T::Helpers
  include GitHub::Memoizer

  # Needed for params method
  requires_ancestor { ApplicationController }

  def record_retention_period_metric(metric, collector)
    if GitHub.flipper[:contribution_retention_period].enabled?(this_user)
      base_date = collector.time_range.end
      summarizable_year = base_date.year < Time.current.year
      inside_retention_period = base_date >= Contribution.retention_period.begin

      tags = [
        "summarizable_year:#{summarizable_year}",
        "retention_period:#{Contribution::RETENTION_DURATION.iso8601}",
        "inside_retention_period:#{inside_retention_period}",
        "org_scoped:#{collector.organization_id.present?}",
      ]

      GitHub.dogstats.increment("contribution.#{metric}", tags: tags)
    end
  end

  # Public: Should the 'Activity overview' section be shown on this user's profile?
  def activity_overview_enabled?
    return @activity_overview_enabled if defined? @activity_overview_enabled

    profile_settings = this_user.profile_settings
    @activity_overview_enabled = profile_settings.activity_overview_enabled?
  end

  def show_teams?
    # Don't show teams when a particular organization filter has not been applied
    return false unless scoped_organization

    now = Time.zone.now
    cutoff = 366.days

    # Ensure the date range is for a recent period, so the teams the user currently
    # belongs to should be relevant
    if params[:from].present?
      from = parse_date_from(params[:from])
      return false if from && from <= now && (now - from) > cutoff
    end

    if params[:to].present?
      to = parse_date_from(params[:to])
      return false if to && to <= now && (now - to) > cutoff
    end

    true
  end

  def this_user
    return @user if defined?(@user)
    @user = User.find_by_login(params[:user_id]) if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
  end

  def viewing_own_profile?
    this_user == current_user
  end

  def scoped_organization
    return @scoped_organization if defined? @scoped_organization

    if activity_overview_enabled?
      org_login = params[:org]
      @scoped_organization = org_login && Organization.find_by_login(org_login)
    else
      @scoped_organization = nil
    end
  end

  def month_date_params
    from = parse_date_from(params[:from]) if params[:from].present?
    to = parse_date_from(params[:to]) if params[:to].present?

    if from.nil? && to.nil?
      to = Time.zone.now
      from = to.beginning_of_month
    else
      to ||= from
      from ||= to
    end

    to = [to, from + 31.days].min

    from = from.beginning_of_day
    to = to.end_of_day

    [from, to]
  end

  # Public: Parse a date string into a time in the current time zone.
  #
  # date_attr - a String like "2018-09-27" in the format YYYY-MM-DD
  #
  # Returns a Time or nil.
  def parse_date_from(raw_date_str)
    date_str = (raw_date_str || "")[0..9]
    return unless date_str =~ /\d{4}-\d{2}-\d{2}/

    begin
      Time.zone.parse(date_str)
    rescue ArgumentError
      nil
    end
  end

  # We use a custom timeout to avoid unicorns on user profiles
  # like reported in https://github.com/github/github/issues/72326
  DIFF_TIMEOUT = 2
  def pr_contribution_diff_timeout
    DIFF_TIMEOUT
  end

  memoize def timeline_collector
    from, to = month_date_params
    time_range = from..to

    organization_id = if activity_overview_enabled?
      scoped_organization&.id
    end

    # When we're simulating the contribution retention period, don't include commit contributions to simulate them
    # being purged from the database.
    #
    # This is the collector used for activity detail. Profiles::ContributionGraphDependency#non_graphql_calendar_collector
    # instantiates its own collector which will include commit contributions to simulate them being included in a
    # contribution summary.
    contribution_classes = Contribution::Collector::CONTRIBUTION_CLASSES
    if GitHub.flipper[:contribution_retention_period].enabled?(this_user) && time_range.begin < Contribution.retention_period.begin
      contribution_classes -= [Contribution::CreatedCommit]
    end

    collector = Contribution::Collector.new(
      user: this_user,
      viewer: current_user,
      time_range: time_range,
      organization_id: organization_id,
      excluded_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations),
      lightweight: true,
      contribution_classes: contribution_classes,
    )

    # Preload data to avoid N+1 queries when rendering the timeline
    Profiles::User::TimelineContributionPreloader.preload(collector: collector)

    collector
  end
end
