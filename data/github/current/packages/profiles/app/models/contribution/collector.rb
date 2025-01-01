# typed: false
# frozen_string_literal: true

class Contribution::Collector
  include Scientist

  CACHE_VERSION = 1

  CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS = [
    Contribution::AnsweredDiscussion,
    Contribution::CreatedCommit,
    Contribution::CreatedDiscussion,
    Contribution::CreatedIssue,
    Contribution::CreatedPullRequest,
    Contribution::CreatedRepository,
    Contribution::CreatedPullRequestReview,
  ].freeze

  CONTRIBUTION_CLASSES_NOT_ASSOCIATED_WITH_REPOS = [
    Contribution::JoinedOrganization,
    Contribution::JoinedGitHub,
    Contribution::EnterpriseContributionInfo,
  ].freeze

  # When updating this default list, make sure to also update the
  # description in user.contributionCollections GraphQL field.
  CONTRIBUTION_CLASSES = (CONTRIBUTION_CLASSES_ASSOCIATED_WITH_REPOS + CONTRIBUTION_CLASSES_NOT_ASSOCIATED_WITH_REPOS).freeze

  # How we map contribution classes to categories for the highlights section
  # of the profile
  CONTRIBUTION_COUNT_NAME_MAPPING = {
    "Contribution::CreatedCommit" => "Commits",
    "Contribution::CreatedIssue" => "Issues",
    "Contribution::CreatedPullRequest" => "Pull requests",
    "Contribution::CreatedPullRequestReview" => "Code review",
  }

  class DataNotAvailable < StandardError; end

  attr_reader :user, :viewer, :contribution_classes, :time_range,
    :organization_id, :excluded_organization_ids

  def initialize(
    user:,
    time_range:,
    contribution_classes: nil,
    viewer: nil,
    organization_id: nil,
    earliest_activity_time: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    @user = user
    @viewer = viewer
    @time_range = time_range
    @contribution_classes = (contribution_classes || CONTRIBUTION_CLASSES) - @user.flagged_contribution_classes
    @first_contributions = {}
    @organization_id = organization_id
    @earliest_activity_time = earliest_activity_time
    @excluded_organization_ids = excluded_organization_ids || []
    @lightweight = lightweight
    @use_contribution_fetchers = GitHub.flipper[:contribution_fetchers].enabled?(user)

    @accessor = Contribution::Accessor.new(
      user: user,
      viewer: viewer,
      contribution_classes: @contribution_classes,
      date_range: time_range.begin.to_date..time_range.end.to_date,
      organization_id: organization_id,
      skip_restricted: !count_restricted_contributions?,
      excluded_organization_ids: @excluded_organization_ids,
      lightweight: lightweight,
      use_contribution_fetchers: @use_contribution_fetchers,
    )
  end

  def use_contribution_fetchers?
    @use_contribution_fetchers
  end

  def lightweight?
    @lightweight
  end

  def started_at
    time_range.begin
  end

  def ended_at
    time_range.end
  end

  # Public: The total count of restricted contributions for the user.
  #
  # Returns an Integer.
  def restricted_contributions_count
    @accessor.restricted_contributions_count
  end

  def contribution_count_by_day
    @accessor.counts_by_day
  end

  # Public: Returns a relation of Organizations in which this user had visible contributions
  # (relative to the viewer).
  #
  # selected_organization_id - optional database ID of an Organization that should definitely
  #                            be included in the results, even if there were no contributions
  #
  # Returns an ActiveRecord::Relation for Organization.
  def organizations_contributed_to(selected_organization_id: nil)
    # If the collector is scoped by an organization,
    # `repository_ids` will only have repos within that org,
    # so this method would only return the scoping org (or empty array).
    raise DataNotAvailable if @organization_id

    owner_ids = Repository.active.where(id: visible_repository_ids).distinct.pluck(:owner_id)
    owner_ids << selected_organization_id unless owner_ids.include?(selected_organization_id)
    owner_ids = owner_ids - @excluded_organization_ids if @excluded_organization_ids.any?

    scope = Organization.where(id: owner_ids).filter_spam_for(@viewer)
    Organization.ranked_for(@user, scope: scope)
  end

  # Public: Whether the time span being viewed ends in the current month.
  #
  # Returns a Boolean.
  def ends_in_current_month?
    today = Date.current
    same_year = (today.year == time_range.end.year)
    same_month = (today.month == time_range.end.month)
    same_year && same_month
  end

  def starts_in_prior_year?
    time_range.begin.year < Date.current.year
  end

  # Public: Get the time span this collector represents in date form.
  #
  # Returns a Range of Dates.
  def date_range
    @date_range ||= started_at.to_date..ended_at.to_date
  end

  # Public: Returns an Array of the years a user has been contributing with the most recent year
  # first.
  # e.g., [2016, 2015, 2014, ...]
  def contribution_years
    (earliest_activity_time.year..Time.zone.today.year).to_a.reverse
  end

  # Public: Get a fetcher to determine the most recent time span before this collector in which the
  # user had contributions. Will only go as far back as the beginning of the year of this collector.
  # Used for showing a message like "May - July 2018: so-n-so had no activity during this period"
  # on the user profile.
  #
  # Returns a Contribution::PriorActivityCollectorFetcher.
  def prior_activity_fetcher
    @prior_activity_fetcher ||= Contribution::PriorActivityCollectorFetcher.new(collector: self)
  end

  # Public: Returns an array of ContributionCount objects (in descending order)
  # each corresponding to the count of the number of contributions for a given
  # contribution class.  Includes restricted contributions & visible
  def contribution_counts
    return @contribution_counts if @contribution_counts

    counts = Hash.new { |h, k| h[k] = Contribution::TypeCount.new(contribution_type: k) }

    @accessor.counts_by_class_name.each do |class_name, count|
      contribution_type = CONTRIBUTION_COUNT_NAME_MAPPING[class_name]
      counts[contribution_type].count += count if contribution_type
    end

    # Biggest contribution types first
    contrib_counts = counts.values.sort_by(&:count).reverse
    total_count = contrib_counts.sum(&:count)
    remainder = 100

    # This uses the `largest remainder method` in order to ensure we always get 100%
    # https://en.wikipedia.org/wiki/Largest_remainder_method
    # It basically says round all percentages down and add the remainder percents to values with
    # the largest remainder
    contrib_counts.each do |contrib_count|
      contrib_count.percentage = contrib_count.count / total_count.to_f * 100
    end

    sorted_by_remainder = contrib_counts
      .sort_by { |contrib_count| contrib_count.percentage % 1 }
      .reverse

    contrib_counts.each do |contrib_count|
      percent = contrib_count.percentage.floor
      contrib_count.percentage = percent
      remainder -= percent
    end

    sorted_by_remainder.each_with_index do |contrib_count, index|
      contrib_count.percentage = contrib_count.percentage.floor

      if index < remainder
        contrib_count.percentage += 1
      end
    end

    @contribution_counts = contrib_counts
  end

  # Public: Returns an array of RepositoryContributionCount objects (in descending order)
  # each corresponding to the count of the number of contributions for a given
  # repository.  Includes visible contributions only.
  def repository_contribution_counts
    return @repository_contribution_counts if @repository_contribution_counts

    counts = @accessor.visible_counts_by_repository_id.map do |repository_id, count|
      Contribution::RepositoryContributionCount.new(id: repository_id, count: count)
    end

    @repository_contribution_counts = counts.sort_by { |rcc| -rcc.count } # sort desc
  end

  # Public: Returns contributions of the specified type the viewer can access.
  #
  # Array of Contribution objects.
  def visible_contributions_of(contribution_class)
    @accessor.visible_contributions_of(contribution_class)
  end

  # Public: Returns true if the user should be able to see more activity in
  # their timeline if they keep hitting 'show more activity'.
  def has_activity_in_the_past?
    started_at.beginning_of_month > earliest_activity_time
  end

  # Public: Returns the time the user's first activity occurred on GitHub. Can predate their join
  # date if old commits were pushed or old issues were imported from another site.
  def earliest_activity_time
    @earliest_activity_time ||= [user.created_at, earliest_issue_time,
                                 earliest_commit_time].compact.min
  end

  def earliest_enterprise_contribution_date
    enterprise_contributions.first&.occurred_at
  end

  def latest_enterprise_contribution_date
    enterprise_contributions.last&.occurred_at
  end

  def earliest_restricted_contribution_date
    @accessor.earliest_restricted_contribution_date
  end

  def latest_restricted_contribution_date
    @accessor.latest_restricted_contribution_date
  end

  def enterprise_contributions
    @accessor.visible_contributions_of(Contribution::EnterpriseContributionInfo).to_a
  end

  def total_enterprise_contributions
    enterprise_contributions.sum(&:contributions_count)
  end

  def async_enterprise_contributions_user_profile_url
    contribution = enterprise_contributions.first
    return Promise.resolve(nil) unless contribution

    # The URL can be for an EnterpriseInstallation or Business
    contribution.enterprise_contribution.async_enterprise_installation.then do |enterprise_installation|
      if enterprise_installation.present?
        enterprise_installation.profile_url_for(user).to_s
      else
        contribution.enterprise_contribution.async_business.then do |business|
          "/enterprises/#{business.slug}"
        end
      end
    end
  end

  # Public: The url of the GitHub Enterprise profile for the user on the installation that sent the
  # (first) contribution count.
  def enterprise_contributions_user_profile_url
    async_enterprise_contributions_user_profile_url.sync
  end

  # Public: Returns whether any contributions exists of the given type with an ID lower
  # than the given subject_id.
  #
  # subject_id - The ID of the subject to check against.
  #
  # Returns a boolean.
  def any_contribution_before?(contribution_class, subject)
    return false unless subject
    @accessor.any_contribution_before?(contribution_class, subject)
  end

  # Public: Returns the first contribution of the given type by respecting the
  # time range. Might return nil in case the viewer cannot access
  # the first contribution or it did not happen within the time range.
  #
  # contribution_class - Contribution type.
  #
  # Returns nil, Contribution, or RestrictedContribution.
  def first_contribution_of(contribution_class)
    return @first_contributions[contribution_class] if @first_contributions.key?(contribution_class)

    contribution = @accessor.load_first(contribution_class)

    @first_contributions[contribution_class] = if contribution.nil?
      nil
    elsif contribution.restricted?
      contribution if count_restricted_contributions?
    else
      contribution
    end
  end

  # Get the contribution for when the user signed up for a GitHub account.
  #
  # Returns a Contribution::JoinedGitHub.
  def joined_github_contribution
    first_contribution_of(Contribution::JoinedGitHub)
  end

  def first_repository_contribution
    first_contribution_of(Contribution::CreatedRepository)
  end

  # Public: Get contributions representing each repository the user created in this time frame.
  #
  # exclude_first - whether to exclude the user's first repository ever; Boolean
  # order_by - optional hash for ordering contributions; valid keys include :field and :direction;
  #   :field - can be "occurred_at"
  #   :direction - can be "ASC" or "DESC"
  #
  # Returns an Array of Contribution::CreatedRepository objects.
  def repository_contributions(exclude_first: false)
    contributions = @accessor.visible_contributions_of(Contribution::CreatedRepository)
    if exclude_first && (contrib = first_repository_contribution)
      contributions -= [contrib]
    end
    contributions
  end

  # Public: Get the user's first Issue contribution, if it was made in this time range.
  #
  # Returns a Contribution::CreatedIssue or nil.
  def first_issue_contribution
    first_contribution_of(Contribution::CreatedIssue)
  end

  # Public: Get the user's first PullRequest contribution, if it was made in this time range.
  #
  # Returns a Contribution::CreatedPullRequest or nil.
  def first_pull_request_contribution
    first_contribution_of(Contribution::CreatedPullRequest)
  end

  # Public: Get the most commented issue created by the user in the time range.
  #
  # Returns a Contribution::CreatedIssue or nil.
  def popular_issue_contribution
    return @popular_issue_contribution if defined? @popular_issue_contribution

    contribution = issue_contributions(exclude_first: true).max_by(&:comments_count)
    @popular_issue_contribution = if contribution && contribution.comments_count > 0
      contribution
    end
  end

  # Public: Get a list of pull request reviews the user opened in this time frame.
  #
  # Returns a sorted Array of CreatedPullRequestReviews.
  def pull_request_review_contributions
    @accessor.visible_contributions_of(Contribution::CreatedPullRequestReview).to_a
  end

  # Public: Get the PullRequests opened by the user in this time frame.
  #
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most comment issue; Boolean
  # order_by - Hash describing how to sort the contributions; valid keys:
  #   :field - valid values include "occurred_at"
  #   :direction - valid values include "ASC" or "DESC"
  #
  # Returns an Array of Contribution::CreatedPullRequests.
  def pull_request_contributions(exclude_first: false, exclude_popular: false)
    contributions = @accessor.visible_contributions_of(Contribution::CreatedPullRequest)

    if exclude_first
      if use_contribution_fetchers?
        first_subject = contributions.min do |a, b|
          a.created_at == b.created_at ? a.id <=> b.id : a.created_at <=> b.created_at
        end
        unless any_contribution_before?(Contribution::CreatedPullRequest, first_subject)
          contributions -= [first_subject]
        end
      elsif contrib = first_pull_request_contribution
        contributions -= [contrib]
      end
    end

    if exclude_popular
      contrib = popular_pull_request_contribution
      contributions -= [contrib] if contrib
    end

    contributions
  end

  # Public: How many repositories visible to the viewer that the user made commits in.
  #
  # Returns an integer.
  def commit_contribution_repo_count
    commit_contributions.group_by(&:repository_id).size
  end

  # Public: How many repositories visible to the viewer that the user opened pull requests in.
  #
  # Returns an integer.
  def pull_request_contribution_repo_count(exclude_first: false, exclude_popular: false)
    contributions = pull_request_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
    contributions.group_by(&:repository_id).size
  end

  # Public: Get the user's opened pull requests, grouped by repository, as a list.
  #
  # max_repos - how many repositories to include; defaults to 25
  # exclude_first - whether to exclude the user's first pull request ever; Boolean
  # exclude_popular - whether to exclude the user's most commented pull request; Boolean
  #
  # Returns an Array of Contribution::ContributionsByRepositories.
  def pull_request_contributions_by_repository(max_repos: 25, exclude_first:, exclude_popular:)
    hash = grouped_pull_request_contributions(max_repos: max_repos, exclude_first: exclude_first, exclude_popular: exclude_popular)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::CreatedPullRequest
      )
    end
  end

  # Public: Returns an Array of Contribution::CreatedCommit objects.
  def commit_contributions
    @accessor.visible_contributions_of(Contribution::CreatedCommit)
  end

  # Public: Returns an Array of Contribution::JoinedOrganization objects.
  def joined_organization_contributions
    @accessor.visible_contributions_of(Contribution::JoinedOrganization).to_a
  end

  def total_contributed_commits
    commit_contributions.sum(&:commit_count)
  end

  # Public: Get a count of how many different repositories the viewer can see that the user left
  # reviews in.
  #
  # Returns an Integer.
  def pull_request_review_repo_count
    pull_request_review_contributions_by_repo.size
  end

  # Public: Get a count of how many issues the user opened in this time frame.
  #
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most comment issue; Boolean
  #
  # Returns an Integer.
  def total_issue_contributions(exclude_first: false, exclude_popular: false)
    issue_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular).size
  end

  # Public: Get a count of how many discussions the user answered in this time frame.
  #
  # Returns an Integer.
  def total_answered_discussion_contributions
    answered_discussion_contributions.size
  end

  # Public: Get a count of how many discussions the user opened in this time frame.
  #
  # Returns an Integer.
  def total_discussion_contributions
    discussion_contributions.size
  end

  # Public: Get a count of how many repositories the user created in this time frame that the
  # viewer can access.
  #
  # exclude_first - whether to exclude the user's first repository ever; Boolean
  #
  # Returns an Integer.
  def total_repository_contributions(exclude_first: false)
    repository_contributions(exclude_first: exclude_first).size
  end

  # Public: Get a count of how many pull requests the user opened in this time frame.
  #
  # exclude_first - whether to exclude the user's first pull request ever; Boolean
  # exclude_popular - whether to exclude the user's most comment pull request; Boolean
  #
  # Returns an Integer.
  def total_pull_request_contributions(exclude_first: false, exclude_popular: false)
    pull_request_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular).size
  end

  # Public: Get a count of how many pull request reviews the user left in this time frame.
  #
  # Returns an Integer.
  def total_pull_request_review_contributions
    pull_request_review_contributions.size
  end

  # Public: Get the Issues opened by the user in this time frame.
  #
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most comment issue; Boolean
  # order_by - Hash describing how to sort the contributions; valid keys:
  #   :field - valid values include "occurred_at"
  #   :direction - valid values include "ASC" or "DESC"
  #
  # Returns an Array of Contribution::CreatedIssues.
  def issue_contributions(exclude_first: false, exclude_popular: false)
    contributions = @accessor.visible_contributions_of(Contribution::CreatedIssue)

    if exclude_first && contrib = first_issue_contribution
      contributions -= [contrib]
    end

    if exclude_popular && (contrib = popular_issue_contribution)
      contributions -= [contrib]
    end

    contributions
  end

  def answered_discussion_contributions
    @accessor.visible_contributions_of(Contribution::AnsweredDiscussion)
  end

  def discussion_contributions
    @accessor.visible_contributions_of(Contribution::CreatedDiscussion)
  end

  # Public: Get the user's opened issues, grouped by repository, as a list.
  #
  # max_repos - how many repositories to include; defaults to 25
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most commented issue; Boolean
  #
  # Returns an Array of Contribution::ContributionsByRepositories.
  def issue_contributions_by_repository(max_repos: 25, exclude_first:, exclude_popular:)
    hash = grouped_issue_contributions(max_repos: max_repos, exclude_first: exclude_first, exclude_popular: exclude_popular)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::CreatedIssue
      )
    end
  end

  def answered_discussion_contributions_by_repository(max_repos: 25)
    hash = grouped_answered_discussion_contributions(max_repos: max_repos)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::AnsweredDiscussion
      )
    end
  end

  def discussion_contributions_by_repository(max_repos: 25)
    hash = grouped_discussion_contributions(max_repos: max_repos)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::CreatedDiscussion
      )
    end
  end

  # Public: Get the user's commit contributions, grouped by repository, as a list.
  #
  # max_repos - how many repositories to include
  #
  # Returns an Array of Contribution::ContributionsByRepository.
  def commit_contributions_by_repository(max_repos:)
    hash = grouped_commit_contributions(max_repos: max_repos)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::CreatedCommit
      )
    end
  end

  # Public: Get the user's PR review contributions, grouped by repository, as a list.
  #
  # max_repos - how many repositories to include; defaults to 25
  #
  # Returns an Array of Contribution::ContributionsByRepository.
  def pull_request_review_contributions_by_repository(max_repos: 25)
    hash = grouped_pull_request_review_contributions(max_repos: max_repos)
    hash.map do |repo, contribs|
      Contribution::ContributionsByRepository.new(
        repository: repo, contributions: contribs, user: user, time_range: time_range,
        contribution_type: Contribution::CreatedPullRequestReview
      )
    end
  end

  # Public: Get the most commented pull request created by the user in the time range.
  #
  # Returns a Contribution::CreatedPullRequest or nil.
  def popular_pull_request_contribution
    return @popular_pull_request_contribution if defined? @popular_pull_request_contribution

    contributions = pull_request_contributions(exclude_first: true)
    contribution = Contribution::CreatedPullRequest.most_popular_from(contributions)

    @popular_pull_request_contribution = if contribution
      contribution
    end
  end

  # Public: returns the first visible contribution of any type in the time range the user
  # can access.
  #
  # Returns Contribution
  def first_visible_contribution
    return @first_visible_contribution if defined? @first_visible_contribution

    first_contributions = @contribution_classes.map do |contribution_class|
      @accessor.first_visible_contribution(contribution_class)
    end

    @first_visible_contribution = first_contributions.compact.min_by(&:occurred_at)
  end

  # Public: Indicates whether there are any restricted or visible contributions in the
  # time range that match the given organization filter, if any.
  #
  # Returns a Boolean.
  def any_contribution?
    # Don't try to calculate contributions for large bots, it will be too slow.
    return false if user.large_bot_account?

    return true if any_restricted_contribution?

    @contribution_classes.each do |contribution_class|
      return true if @accessor.visible_contributions_of(contribution_class).any?
    end

    false
  end

  # Public: Does the user have any restricted contributions?
  #
  # Returns a Boolean.
  def any_restricted_contribution?
    restricted_contributions_count > 0
  end

  # Public: Whether or not the collector's time span is all within the same day.
  #
  # Returns a Boolean.
  def single_day?
    date_range.end == date_range.begin
  end

  # Public: Get a count of how many different repositories visible to the viewer that the user
  # opened issues in.
  #
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most comment issue; Boolean
  #
  # Returns an Integer.
  def issue_contribution_repo_count(exclude_first: false, exclude_popular: false)
    contributions = issue_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
    contributions.group_by(&:repository).size
  end

  # Public: Get a count of how many different repositories visible to the viewer that the user
  # answered discussions in.
  #
  # Returns an Integer.
  def answered_discussion_contribution_repo_count
    answered_discussion_contributions.group_by(&:repository).size
  end

  # Public: Get a count of how many different repositories visible to the viewer that the user
  # opened discussions in.
  #
  # Returns an Integer.
  def discussion_contribution_repo_count
    discussion_contributions.group_by(&:repository).size
  end

  def visible_repository_ids
    @accessor.visible_counts_by_repository_id.keys
  end

  private

  # Private: Get issue contributions grouped by repository and ordered with the repositories having
  # the most contributions first. Limited to the specified number of repositories (that is, groups).
  #
  # max_repos - how many repositories to include; defaults to 25
  # exclude_first - whether to exclude the user's first issue ever; Boolean
  # exclude_popular - whether to exclude the user's most commented issue; Boolean
  #
  # Returns a Hash of Repository => Array of Contribution::CreatedIssues.
  def grouped_issue_contributions(max_repos: 25, exclude_first:, exclude_popular:)
    contributions = issue_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
    hash = contributions.group_by(&:repository)
    hash.sort_by { |_repo, contribs| -contribs.size }.take(max_repos).to_h
  end

  def grouped_discussion_contributions(max_repos: 25)
    contributions = discussion_contributions
    hash = contributions.group_by(&:repository)
    hash.sort_by { |_repo, contribs| -contribs.size }.take(max_repos).to_h
  end

  def grouped_answered_discussion_contributions(max_repos: 25)
    contributions = answered_discussion_contributions
    hash = contributions.group_by(&:repository)
    hash.sort_by { |_repo, contribs| -contribs.size }.take(max_repos).to_h
  end

  # Private: Get pull request review contributions grouped by repository and ordered with the
  # repositories having the most review contributions first. Limited to the specified number of
  # repositories (that is, groups).
  #
  # max_repos - how many repositories to include; defaults to 25
  #
  # Returns a Hash of Repository => Array of Contribution::CreatedPullRequestReviews.
  def grouped_pull_request_review_contributions(max_repos: 25)
    pull_request_review_contributions_by_repo.
      sort_by { |_repo, contributions| -contributions.size }.
      take(max_repos).
      to_h
  end

  # Private: Get commit contributions grouped by repository and ordered with the repositories
  # having the most commits first. Limited to the specified number of repositories (that is,
  # groups).
  #
  # max_repos - how many repositories to include
  #
  # Returns a hash of Repository => [CreatedCommit...].
  def grouped_commit_contributions(max_repos:)
    commit_contributions.group_by(&:repository).
      sort_by { |_repo, contributions| -contributions.sum(&:commit_count) }.
      take(max_repos).
      to_h
  end

  # Private: Get pull request contributions grouped by repository and ordered with the repositories
  # having the most PR contributions first. Limited to the specified number of repositories (that
  # is, groups).
  #
  # max_repos - how many repositories to include; defaults to 25
  # exclude_first - whether to exclude the user's first pull request ever; Boolean
  # exclude_popular - whether to exclude the user's most commented pull request; Boolean
  #
  # Returns a Hash of Repository => Array of Contribution::CreatedPullRequests.
  def grouped_pull_request_contributions(max_repos: 25, exclude_first:, exclude_popular:)
    contributions = pull_request_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
    hash = contributions.group_by(&:repository)
    hash.sort_by { |_repo, contributions| -contributions.size }.take(max_repos).to_h
  end

  def earliest_issue_time
    issues = user
      .issues
      .includes(:repository)
      .select(:contributed_at_offset, :contributed_at_timestamp, :created_at, :repository_id)
      .order(:created_at)
      .limit(Contribution::CreatedIssue::LIMIT_FOR_FIRST_ISSUE_QUERY)

    issue = if @user != @viewer && !count_restricted_contributions?
      issues.find { |issue| issue.repository&.public? } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    else
      issues.first # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    issue&.contribution_time
  end

  def earliest_commit_time
    return if @user != @viewer && !count_restricted_contributions?

    CommitContributions.domain.first_contribution_date(user: user)&.beginning_of_day
  end

  def pull_request_review_contributions_by_repo
    pull_request_review_contributions.group_by(&:repository)
  end

  def profile_settings
    @user.profile_settings
  end

  def platform_type_name
    "ContributionsCollection"
  end

  # Private: Should restricted contributions be counted?
  #
  # Returns a Boolean.
  def count_restricted_contributions?
    return @count_restricted_contributions if defined? @count_restricted_contributions

    @count_restricted_contributions = profile_settings.show_private_contribution_count? &&

      # Don't count private contributions when filtering by an organization because
      # that could reveal information about where a user is contributing.
      @organization_id.nil?
  end
end
