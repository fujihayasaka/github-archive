# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module ProfilesHelper
  include HydroHelper
  include GitHub::Memoizer

  COMMIT_CONTRIBUTIONS_PATH_TEMPLATE = Addressable::Template.new("/{owner}/{repo}/commits?author={author}&since={since}&until={until}")

  memoize def async_contributions_enabled?
    FeatureFlag.vexi.enabled?(:profiles_async_contributions, current_user, default: false)
  end

  memoize def no_referrer_anon_rate_limit_enabled?
    !logged_in? && request.referrer.blank? && async_contributions_enabled?
  end

  def profiles_rate_limit_key
    return default_rate_limit_key unless no_referrer_anon_rate_limit_enabled?

    session_id = request.env.dig("rack.session", "session_id")
    return default_rate_limit_key if session_id.blank?

    "#{self.class.to_s.underscore}.#{action_name}:#{session_id}"
  end

  def profiles_rate_limit_max
    return 100 unless no_referrer_anon_rate_limit_enabled?
    30
  end

  def profiles_rate_limit_ttl
    return GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL unless no_referrer_anon_rate_limit_enabled?
    30.seconds
  end

  # Public: Returns whether a private profile setting can be overridden.
  #         Only `true` for staff with the `private_profile_override` query param. `false` otherwise.
  def private_profile_override?
    current_user&.site_admin? && params[:private_profile_override]
  end

  def most_recent_collector_with_activity(collector)
    return unless collector

    fetcher = collector.prior_activity_fetcher
    fetcher.collector_with_activity
  end

  def most_recent_collector_without_activity(collector)
    return unless collector

    fetcher = collector.prior_activity_fetcher
    fetcher.collector_without_activity
  end

  # Public: True if the profile readme should be rendered
  #         for this viewer
  def show_profile_readme?
    return false unless this_user

    this_user.profile_readme_visible?
  end

  def show_profile_readme_info?(repository, user, filename = "README.md")
    return false if repository.nil?
    return false if user.nil?
    return false unless PreferredFile.filename_is_type?(filename: filename, type: :readme)
    return false if repository.owner != user
    return false if user.is_enterprise_managed?

    repository.user_configuration_repository?
  end

  # How many repositories should we show in a contribution rollup before we
  # collapse the section by default?
  REPO_ROLLUP_COLLAPSE_THRESHOLD = 7

  # Public: Get the given time as an ISO8601 date string in the viewer's time zone.
  #
  # time - UTC DateTime
  #
  # Returns a String like "2018-05-01".
  def timeline_iso8601_date(time)
    time.in_time_zone(Time.zone).to_date.iso8601
  end

  # Public: Get the year for the given DateTime in the current viewer's time zone.
  #
  # started_at - UTC DateTime for the beginning of the contributions collection time range
  #
  # Returns a String like "2018".
  def timeline_year_str(started_at)
    started_at.in_time_zone(Time.zone).strftime("%Y")
  end

  def contributions_date_range_label(earliest_date:, latest_date:)
    if earliest_date > latest_date
      earliest_date, latest_date = latest_date, earliest_date
    end
    earliest_date = earliest_date.in_time_zone(Time.zone)
    latest_date = latest_date.in_time_zone(Time.zone)
    date_format = "%b %-d" # e.g. "May 12"

    if latest_date == earliest_date
      earliest_date.strftime(date_format)
    else
      "#{earliest_date.strftime(date_format)} – #{latest_date.strftime(date_format)}"
    end
  end

  # Public: Returns a hex color String in the format "#ff00ff" to represent
  # the given percentage.
  #
  # percentage - Integer from 0-100
  # colors - an optional Array of at least 4 color Strings
  #
  # Returns a String.
  def commit_percentage_color(percentage, colors = [])
    if percentage <= 25
      colors[0] || Contribution::Calendar::DEFAULT_COLORS[0]
    elsif percentage <= 50
      colors[1] || Contribution::Calendar::DEFAULT_COLORS[1]
    elsif percentage <= 75
      colors[2] || Contribution::Calendar::DEFAULT_COLORS[2]
    else
      colors[3] || Contribution::Calendar::DEFAULT_COLORS[3]
    end
  end

  def commit_percentage_for_repo(repo_commit_count:, total_commit_count:)
    pct = 100 * repo_commit_count / total_commit_count.to_f
    pct.ceil
  end

  # Public: Get a count of how many repositories were not shown in the issue/pull request rollup.
  #
  # total_repos - how many repositories had contributions in them from the user; integer
  #
  # Returns an integer.
  def repo_count_not_shown_in_rollup(total_repos:)
    [total_repos - ProfilesController::REPOS_PER_ROLLUP_LIMIT, 0].max
  end

  # Public: Get a count of how many contributions were not shown in a rollup.
  #
  # total_contributions - how many contributions there were total; integer
  #
  # Returns an integer.
  def contrib_count_not_shown_in_rollup(total_contributions)
    [total_contributions - ProfilesController::CONTRIBS_PER_REPO_LIMIT, 0].max
  end

  # Public: Determine if the repositories in a rollup in the timeline should be shown by default.
  #
  # total_repos - how many repositories had contributions from the user; integer
  #
  # Returns a Boolean.
  def expand_repo_rollup?(total_repos)
    total_repos < REPO_ROLLUP_COLLAPSE_THRESHOLD
  end

  # Public: Get a short date in the viewer's time zone for display in the user timeline.
  #
  # occurred_at - UTC DateTime for when the contribution was made
  #
  # Returns a String.
  def contribution_short_date(occurred_at)
    occurred_at.in_time_zone(Time.zone).strftime("%b %-d")
  end

  # Public: Get the month, day, and year in the viewer's time zone for display in the user timeline.
  #
  # occurred_at - UTC DateTime for when the contribution was made
  #
  # Returns a String.
  def contribution_long_date(occurred_at)
    occurred_at.in_time_zone(Time.zone).strftime("%B %-d, %Y")
  end

  # Public: Get the month name in the viewer's time zone for a given commit time.
  #
  # occurred_at - UTC DateTime for when the contribution was made
  #
  # Returns a String.
  def commit_contribution_month(occurred_at)
    occurred_at.in_time_zone(Time.zone).strftime("%B")
  end

  # Public: Get the header text for the user profile timeline when it has activity.
  #
  # started_at - UTC DateTime for the earliest date in the contributions collection
  # is_single_day - does the collection span only a day; Boolean
  #
  # Returns HTML.
  def time_range_with_activity_header(started_at:, is_single_day:)
    time = started_at.in_time_zone(Time.zone) # convert to viewer's time zone
    parts = [time.strftime("%B")]
    parts << "#{time.strftime("%-d")}," if is_single_day
    parts << tag.span(time.strftime("%Y"), class: "color-fg-muted")
    safe_join(parts, " ")
  end

  # Public: Get 'alt' attribute text for the image that represents a user's first repository.
  #
  # Returns a String.
  def first_repo_image_alt(user_is_viewer:, user_name:)
    if user_is_viewer
      "Congratulations on your first repository!"
    else
      "#{user_name} created their first repository!"
    end
  end

  # Public: Get 'alt' attribute text for the image that represents a user's first issue on GitHub.
  #
  # Returns a String.
  def first_issue_image_alt(user_is_viewer:, user_name:)
    if user_is_viewer
      "Congratulations on your first issue!"
    else
      "#{user_name} created their first issue!"
    end
  end

  # Public: Get 'alt' attribute text for the image that represents a user's first pull request.
  #
  # Returns a String.
  def first_pull_request_image_alt(user_is_viewer:, user_name:)
    if user_is_viewer
      "Congratulations on your first pull request!"
    else
      "#{user_name} created their first pull request!"
    end
  end

  # Public: Get a hash of contribution counts or percentages by contribution type.
  #
  # contribution_counts - an Array of ContributionCount GraphQL objects
  # value - a Symbol representing what the value in the resulting hash should be; choose from
  #         :count or :percentage
  #
  # Returns a Hash like:
  #   `{"Issues" => 3, "Commits" => 4, "Pull requests" => 20, "Code review" => 0}`
  def contribution_percentages_by_type(contribution_counts)
    values_by_type = {}

    contribution_counts.each do |contrib|
      values_by_type[contrib.contribution_type] = contrib.percentage
    end

    # Make sure we have all the possible labels
    Contribution::Collector::CONTRIBUTION_COUNT_NAME_MAPPING.each_value do |contrib_type|
      values_by_type[contrib_type] ||= 0
    end

    values_by_type
  end

  def contribution_percentages_summary(percentages)
    percentages.map { |key, value| "#{value}% #{key.downcase}" }.join(", ")
  end

  # Public: Get a page title for viewing the previous month of a user's profile.
  #
  # user - User instance for the user whose profile is being viewed
  # date_range - the currently viewed Range of Dates for the profile
  #
  # Returns a String.
  def show_previous_months_contributions_title(user:, date_range:)
    previous_month = date_range.begin.prev_month
    title = "#{user.display_login}"
    title += " (#{user.profile_name})" if user.profile_name.present?
    date = previous_month.end_of_month.to_date
    date_str = date.strftime("%B %Y")
    "#{title} / #{date_str}"
  end

  # Public: Returns the user profile URL for viewing the previous month of contributions, relative
  # to beginning of the current time range.
  #
  # user - the User whose profile is being viewed, or their String login
  # date_range - the currently viewed Range of Dates for the profile
  # org - an Organization or its String login, or nil
  # xhr - whether this is for making an AJAX request or for putting into the URL
  #       for the user to copy and load as a regular HTTP request; Boolean
  #
  # Returns a String.
  def show_previous_months_contributions_path(user:, date_range:, org:, xhr: false)
    previous_month = date_range.begin.prev_month
    from = previous_month.beginning_of_month.to_date
    to = previous_month.end_of_month.to_date
    suffix = "?tab=overview&from=#{from}&to=#{to}"
    suffix += "&include_header=no" if xhr
    suffix += "&org=#{org}" if org.present?
    user_path(user) + suffix
  end

  # Public: Get a title for the "Contribution activity" section of the user profile.
  #
  # org_name - String profile name or login for the organization being used to filter activity;
  #            can be nil
  #
  # Returns a String.
  def contribution_activity_title(org_name:)
    prefix = "Contribution activity"
    suffix = "in #{org_name}" if org_name.present?
    [prefix, suffix].compact.join(" ")
  end

  # Public: Returns a url with the correct date parameters for viewing the specified year on a
  # user's timeline.
  #
  # year - year being viewed; Integer
  # user - User whose profile is being viewed, or their login
  # org - String Organization login or nil
  #
  # Returns a String.
  def contribution_year_url(year:, user:, org:)
    url = user_path(user) + "?tab=overview"
    today = Date.current

    if today.year == year.to_i
      url << "&from=#{today.beginning_of_month}"
      url << "&to=#{today}"
    else
      url << "&from=#{year}-12-01"
      url << "&to=#{year}-12-31"
    end

    url << "&org=#{org}" if org.present?
    url
  end

  # Public: Returns true if the user owns the item with the given owner ID.
  #
  # owner_id - ID of the owner of some record
  # user_id - ID of a User such as the current viewer
  #
  # Returns a Boolean.
  def owned_by_user?(owner_id:, user_id:)
    owner_id == user_id
  end

  # Public: Returns data attributes for tracking clicks on the profile page
  #
  # target - Symbol that maps to hydro.schemas.github.v1.UserProfileClick.EventTarget
  #
  # Returns a hash to be passed as `:data` to `link_to`
  def profile_click_tracking_attrs(target, current_user_id: current_user&.id, profile_user_id: this_user&.id)
    return {} unless profile_user_id

    hydro_click_tracking_attributes("user_profile.click",
                                    profile_user_id: profile_user_id,
                                    target: target,
                                    user_id: current_user_id)
  end

  # Public: generate a button that folds a contributions timeline rollup
  #
  # type - either "CATEGORY" or "REPO"
  #
  # Returns HTML
  def profile_rollup_fold_button(type:)
    data = profile_click_tracking_attrs(:"TIMELINE_#{type}_ROLLUP_COLLAPSE")
    content_tag :span, class: "Details-content--open float-right", data: data do
      octicon(:fold, aria: { label: "Collapse" })
    end
  end

  # Public: generate a button that unfolds a contributions timeline rollup
  #
  # type - either "CATEGORY" or "REPO"
  #
  # Returns HTML
  def profile_rollup_unfold_button(type:)
    data = profile_click_tracking_attrs(:"TIMELINE_#{type}_ROLLUP_EXPAND")
    content_tag :span, class: "Details-content--closed float-right", data: data do
      octicon(:unfold, aria: { label: "Expand" })
    end
  end

  # Public: Returns a date range of a contribution collector
  # instance taking the user's time zone into account
  #
  # collector - Contribution::Collector
  #
  # Returns DateRange
  def date_range_in_time_zone(collector)
    start_date = collector.started_at.in_time_zone(Time.zone).to_date
    end_date = collector.ended_at.in_time_zone(Time.zone).to_date
    start_date..end_date
  end

  # Public: Returns a String representing the range of months this view spans.
  #
  # collector - Contribution::Collector
  #
  # Returns nil if a full year from January to December is spanned.
  def timeline_month_range(collector)
    date_range = prior_activity_date_range(collector)

    start_month = date_range.begin.month
    end_month = date_range.end.month

    if start_month == end_month # only viewing one month
      date_range.begin.strftime("%B")
    elsif start_month > 1 || end_month < 12 # not a full year from Jan - Dec
      "#{date_range.begin.strftime("%B")} - #{date_range.end.strftime("%B")}"
    end
  end

  # Public: Returns the time range of prior activity, if the collector
  # before this has activity, then use the next month after the earliest
  # date since there was activity on the earliest date's month
  #
  # collector - Contribution::Collector
  #
  # Returns a date range
  def prior_activity_date_range(collector)
    fetcher = collector.prior_activity_fetcher
    most_recent_collector = fetcher.collector_with_activity || fetcher.collector_without_activity

    earliest_date = most_recent_collector.started_at.in_time_zone(Time.zone)
    latest_date = collector.ended_at.in_time_zone(Time.zone)

    if most_recent_collector.any_contribution?
      no_activity_month = earliest_date.to_date + 1.month
      earliest_date = no_activity_month.in_time_zone(Time.zone)
    end

    earliest_date.to_date..latest_date.to_date
  end

  def org_profile_cache_key(feature:, organization:, direct_or_team_member:, org_profile_overview: false)
    ["#{org_profile_overview ? "v2" : "v1"}:#{feature}", direct_or_team_member, organization.cache_key]
  end

  def user_pronouns_enabled?
    return false if GitHub.enterprise?
    return false unless logged_in?
    return false if this_user&.private_profile_for?(current_user)

    feature_enabled_for_current_user?(feature_name: :user_pronouns)
  end

  # Should the current user see controls related to ORCID integration in their profile settings?
  def show_orcid_controls?
    GitHub.orcid_enabled?
  end

  # Should the current user see ORCID identifiers on a profile?
  #
  # This check is written to take pains not to make additional database queries unless it's actually necessary, to
  # optimize for the far-more-common case when `this_user` does not have an ORCID record. It assumes that the
  # UserMetadata and UserSettings associations are already loaded (or will be loaded elsewhere anyway).
  def show_orcid_identifier?
    # Check the execution environment (GHES/Proxima) and global instance configuration.
    return false unless show_orcid_controls?
    # Check for User presence and the UserMetadata flag.
    return false unless this_user&.has_orcid_record?
    # Check for the UserSettings setting.
    return false unless this_user.display_orcid_id_on_profile?
    # Verify that the record is actually there if the UserMetadata said it was, just in case there was a timing
    # glitch.
    return false unless this_user.orcid_record

    true
  end

  def social_account_icon(social_account, **system_args)
    if social_account.svg_path
      system_args[:classes] = class_names("octicon", system_args[:classes])
      classified = Primer::Classify.call(**system_args)
      svg(social_account.svg_path, title: social_account.title, aria: true, width: 16, height: 16, **classified)
    else
      primer_octicon(social_account.octicon_name, title: social_account.title, **system_args)
    end
  end

  # Public: Verify that the target user's profile should be visible to the current_user
  #
  # Returns nil or renders a 404 response
  def ensure_profile_visible
    return if this_user &&
      !this_user.hide_from_user?(current_user) &&
      !this_user.private_profile_for?(current_user)

    render_404
  end

  # Public: Generate a path to show a user's commit contributions in a particular repo
  #
  # contribution - Contribution::ContributionsByRepository
  #
  # Returns String
  def commit_contributions_path(contribution)
    time_range = contribution.time_range
    repo = contribution.repository

    template_args = {
      owner: repo.owner.display_login,
      repo: repo.name,
      author: contribution.user.display_login,
      since: time_range.begin.beginning_of_day.utc.to_date.iso8601,
      until: (time_range.end.beginning_of_day + 1.day).utc.to_date.iso8601,
    }

    COMMIT_CONTRIBUTIONS_PATH_TEMPLATE.expand(template_args).to_s
  end
end
