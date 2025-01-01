# typed: true
# frozen_string_literal: true

# Tracks daily summaries of commit contribution counts by user and repository.
class CommitContributionSummary < ApplicationRecord::Collab
  class Contribution
    include GitHub::Memoizer

    attr_reader :summary, :commit_count, :day_index

    def initialize(summary, day_index)
      @summary = summary
      @day_index = day_index
      @commit_count = summary.counts[day_index]
    end

    delegate :user, :user_id, :repository, :repository_id, to: :summary

    memoize def committed_date
      Date.new(summary.year, 1, 1) + day_index.days
    end
  end

  # Given a collection of CommitContributionSummary records and an optional date range,
  # provides methods to iterate over daily contribution detail for dates that fall within
  # the date range.
  class ContributionIterator
    include Enumerable

    attr_reader :summaries, :begin_date, :end_date

    def initialize(summaries, date_range = nil)
      @summaries = Array(summaries)
      @begin_date = date_range&.begin
      @end_date = date_range&.end
    end

    # Iterate over all contributions in the given summaries for days that fall within the
    # iterator's date range, and yield a Contribution record for each nonzero contribution
    # day.
    #
    # Summaries are processed in the order given, and contributions within each summary are
    # processed from first to last.
    def each(&block)
      summaries.each do |summary|
        index_range(summary).each do |day_index|
          yield Contribution.new(summary, day_index) if summary.counts[day_index] > 0
        end
      end
    end

    # Iterate over all contributions in the given summaries for days that fall within the
    # iterator's date range, and yield a Contribution record for each nonzero contribution
    # day.
    #
    # Summaries are processed in the order given, and contributions within each summary are
    # processed from last to first.
    def reverse_each(&block)
      summaries.each do |summary|
        index_range(summary).reverse_each do |day_index|
          yield Contribution.new(summary, day_index) if summary.counts[day_index] > 0
        end
      end
    end

    # Return the most recent contribution in the iterator's date range, or nil if there
    # are no contributions in the range.
    #
    # Returns a Contribution record, or nil.
    def last
      reverse_each { |contribution| return contribution }

      nil
    end

    private

    # Whether the given summary covers the iterator's date range. If the date range
    # has a begin date, the summary year may not be for an earlier year; and if the
    # date range has an end date, the summary year may not be for a later year.
    #
    # summary - A CommitContributionSummary record.
    #
    # Returns a Boolean.
    def summary_covers_range?(summary)
      return false if begin_date.present? && summary.year < begin_date.year
      return false if end_date.present? && summary.year > end_date.year
      true
    end

    # The range of indexes in the given summary's counts array that are within the
    # iterator's date range.
    #
    # summary - A CommitContributionSummary record.
    #
    # Returns a Range of Integer indexes, or an empty Array if the summary is
    # outside of the iterator's date range.
    def index_range(summary)
      return [] unless summary_covers_range?(summary)

      first_index = if begin_date.nil? || summary.year > begin_date.year
        0
      else
        begin_date.yday - 1
      end
      first_index = [first_index, summary.first_nonzero_index].max

      last_index = if end_date.nil? || summary.year < end_date.year
        Date.new(summary.year, 12, 31).yday - 1
      else
        end_date.yday - 1
      end
      last_index = [last_index, summary.last_nonzero_index].min

      first_index..last_index
    end
  end

  # Methods for tracking and updating multiple summaries for a repository, eg. during
  # a backfill operation.
  class Collection
    attr_reader :repository

    def initialize(repository:)
      @repository = repository

      # Updates are grouped by user ID and year so we can efficiently find the right
      # one to update, and batch them for writing to the database. They're built as hashes
      # because that's what insert_all uses to batch insert records.
      @updates = Hash.new do |repo_summaries_by_user_id, user_id|
        repo_summaries_by_user_id[user_id] = Hash.new do |user_summaries_by_year, year|
          days_in_year = Date.new(year, 12, 31).yday
          user_summaries_by_year[year] = {
            repository_id: repository.id,
            user_id: user_id,
            year: year,
            counts: Array.new(days_in_year, 0),
            created_at: GitHub::SQL::ArelLiterals::NOW,
            updated_at: GitHub::SQL::ArelLiterals::NOW,
          }
        end
      end
    end

    def add(user_id:, date:, count:)
      summary = @updates[user_id][date.year]
      summary[:counts][date.yday - 1] += count
    end

    # Integrate the counts that have been tracked in this collection into each user's summary
    # records. When the user already has a summary for a year, add tracked counts to existing
    # counts; otherwise build a new summary record and set the counts to the tracked counts.
    #
    # For each user:
    # - load any existing summaries for the user/repo
    # - add tracked count values to existing summary records
    # - save updated summary records in batches
    def update!
      @updates.each do |user_id, updates_by_year|
        GitHub.logger.tagged(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repository.id,
          "gh.user.id" => user_id,
        ) do
          # Start with existing summary records for this repo/user
          summaries_to_update = CommitContributionSummary.
            for_repository(repository).
            for_user(user_id).
            where(year: updates_by_year.keys).
            index_by(&:year)

          # For years where the user has no summary, default to an empty one
          summaries_to_update.default_proc = proc do |summaries, year|
            days_in_year = Date.new(year, 12, 31).yday
            summaries[year] = CommitContributionSummary.new(
              repository_id: repository.id,
              user_id: user_id,
              year: year,
              counts: Array.new(days_in_year, 0),
            )
          end

          # Add in counts that have been tracked in this collection
          updates_by_year.each do |year, updates|
            updates[:counts].each_with_index do |count, day_index|
              summaries_to_update[year].counts[day_index] += count
            end
          end

          # Write them all out
          CommitContributionSummary.with_write do
            summaries_to_update.values.each_slice(INSERT_BATCH_SIZE) do |batch|
              CommitContributionSummary.throttle do
                batch.each do |summary|
                  summary.save!
                rescue ActiveRecord::RecordInvalid
                  # This can happen when a summary was stored after this update! started,
                  # try to load it and merge in values for this year.
                  existing_summary = CommitContributionSummary.
                    for_repository(repository).
                    for_user(user_id).
                    find_by(year: summary.year)
                  raise unless existing_summary

                  updates_by_year[summary.year][:counts].each_with_index do |count, day_index|
                    existing_summary.counts[day_index] += count
                  end

                  existing_summary.save!
                end
              end
            end
          end
        end
      end
    end

    # Write out counts that have been tracked in this collection, overwriting any existing counts.
    #
    # For each user:
    # - delete any existing summaries for the user/repo in batches
    # - insert updated summary records in batches
    def replace!
      @updates.each do |user_id, summaries_by_year|
        GitHub.logger.tagged(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repository.id,
          "gh.user.id" => user_id,
        ) do
          # Remove any existing summaries for this repo/user
          ids = CommitContributionSummary.with_read do
            CommitContributionSummary.for_repository(repository).for_user(user_id).pluck(:id)
          end
          ids.each_slice(DELETE_BATCH_SIZE) do |slice|
            CommitContributionSummary.with_write do
              CommitContributionSummary.throttle { CommitContributionSummary.where(id: slice).delete_all }
            end
          end

          # Write out new summaries in batches
          summaries_by_year.values.each_slice(INSERT_BATCH_SIZE) do |user_summaries|
            user_summaries.each { |summary| summary[:total_count] = summary[:counts].sum }
            CommitContributionSummary.with_write do
              CommitContributionSummary.throttle { CommitContributionSummary.insert_all(user_summaries) }
            end
          end
        end
      end
    end
  end

  # Delete/insert summaries in batches when backfilling a repository.
  DELETE_BATCH_SIZE = 50
  INSERT_BATCH_SIZE = 20

  # TODO: refactor week calculations to eg. lib/github for use by this model and bits in lib/github/repo_graph/eventer
  #
  # Time.at(0).utc is Thursday. Our week starts on Sunday, so we need to compensate for this.
  INITIAL_WEEK_OFFSET = 3.days.to_i

  # A single week, in seconds
  WEEK_TS_DELTA = 1.week.to_i

  # The maximum number of times to retry a throttled operation, used when backfilling a repository.
  MAX_THROTTLE_RETRIES = 5

  # The maximum number of users to backfill at once
  BACKFILL_USER_BATCH_SIZE = 100

  attribute :counts, CompressedIntegerArray.new

  # Ensure that the counts attribute is always an AnnotatedArray so the annotated methods
  # are available.
  def counts=(value)
    super(CompressedIntegerArray::AnnotatedArray.from(value))
  end

  # These values are populated when the compressed summary is deserialized, and can be used to
  # more efficiently determine the first/last contribution dates for sorting etc.
  delegate :first_nonzero_index, :last_nonzero_index, to: :counts

  scope :no_ghost_users, -> { where("user_id <> ?", User.ghost.id) }

  scope :for_user, -> (user) { where(user: user) }
  scope :for_repository, -> (repository) { where(repository: repository) }
  scope :covering_date_range, -> (date_range) { where(year: date_range&.begin&.year..date_range&.end&.year) }

  belongs_to :user
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain

  destroy_in_background_with :repository

  validates :year, presence: true
  validates :year, uniqueness: { scope: [:repository_id, :user_id] }, on: :create
  validates :year, uniqueness: { scope: [:repository_id, :user_id] }, on: :update, if: :year_changed?
  validates :year, numericality: { only_integer: true, greater_than_or_equal_to: 1969 }

  validates :counts, presence: true
  validate :has_at_least_one_contribution, if: -> (summary) { summary.counts.present? }

  before_validation :normalize_counts, if: -> (summary) { summary.year.present? }
  before_save :update_total_count

  # Public: Create/update summaries for all contributors to the specified repository,
  # using existing CommitContribution records as the source of truth for contributions.
  #
  # repository - The Repository to update the summary for.
  #
  # Returns nothing.
  def self.backfill_repository(repository, user = nil)
    # When the :skip_commit_contributions flag is enabled for a repo in summary-enabled environments,
    # there won't be any CommitContribution records to use as the source of truth for contributions.
    #
    # In this case, we can run CommitContribution backfills to crawl the repo and populate the right
    # contribution data.
    if GitHub.commit_contribution_summaries_enabled? && repository.feature_enabled?(:skip_commit_contributions)
      if user.present?
        return CommitContribution.backfill_user!(repository, user, context: "test")
      else
        return CommitContribution.backfill!(repository, true)
      end
    end

    GitHub.logger.tagged(
      "code.namespace" => "CommitContributionSummary",
      "code.function" => "backfill_repository",
      "gh.repo.id" => repository.id,
      "gh.user.id" => user&.id,
    ) do
      contributor_scope = CommitContribution.no_ghost_users.for_repository(repository)
      contributor_scope = contributor_scope.where(user: user) if user
      contributor_ids = with_read { contributor_scope.distinct.pluck(:user_id) }

      # Make sure there are no summaries left for users who have no contributions. This cleans up from cases where
      # update_from_push added summaries in cases where we didn't add corresponding CommitContribution records.
      user_ids_with_summaries = with_read { CommitContributionSummary.for_repository(repository).distinct.pluck(:user_id) }
      extra_user_ids = user_ids_with_summaries - contributor_ids unless user
      if extra_user_ids.present?
        clear_contributions_for(repository: repository, user: extra_user_ids)
      end

      contributor_ids.each_slice(BACKFILL_USER_BATCH_SIZE) do |user_ids|
        GitHub.dogstats.distribution_time("commit_contribution_summary.backfill") do
          contribution_batch = with_read do
            CommitContribution.
              for_repository(repository).
              for_user(user_ids).
              where("commit_count > 0").
              where("committed_date IS NOT NULL").
              pluck(:user_id, :committed_date, :commit_count)
          end

          backfill_summaries = Collection.new(repository: repository)
          contribution_batch.each do |user_id, date, count|
            backfill_summaries.add(user_id: user_id, date: date, count: count)
          end
          backfill_summaries.replace!
        end
      end
    end
  end

  def self.clear_contributions_for(repository:, user:)
    ids = with_read { CommitContributionSummary.for_repository(repository).for_user(user).pluck(:id) }
    ids.each_slice(DELETE_BATCH_SIZE) do |slice|
      throttle { with_write { CommitContributionSummary.where(id: slice).delete_all } }
    end
  end

  # Public: Calculate the timestamp for the beginning of the week (first second in Sunday, UTC)
  #         belonging to the given timestamp.
  #
  # day_ts - an integer (or something that responds to `to_i`) representing an epoch offset.
  #
  # Returns the epoch offset of the last Sunday before the given day_ts.
  def self.week_start(day_ts)
    day_ts = day_ts.to_i

    # timestamp since "first Sunday" (Dec 28th, 1969)
    adjusted_ts = day_ts - INITIAL_WEEK_OFFSET

    # how far are we passed the latest Sunday?
    offset_beyond_sunday = adjusted_ts % WEEK_TS_DELTA

    # subtract that offset into the week to get the latest sunday week timestamp
    day_ts - offset_beyond_sunday
  end

  # Public: Generate a contribution history for the given repository and optional users.
  #
  # repository - The Repository to generate the history for.
  # users - An Array of User objects to generate the history for.
  #
  # Returns a Hash of Hashes, in the same format as returned by
  # GitHub::RepoGraph::ContributionInsights#fetch_contributors_data.
  sig do
    params(repository: Repository, users: T::Array[User]).
      returns(T::Hash[Symbol, T::Hash[String, T::Hash[Integer, Integer]]])
  end
  def self.repository_contribution_history(repository:, users:)
    # Index users by ID so we can find them from each contribution's user_id
    # rather than generating another query for the contribution/summary association.
    users_by_id = users.index_by(&:id)

    # Preload associations used to determine the git_author_email for each user
    preloader = ActiveRecord::Associations::Preloader.new(
      records: users,
      associations: [:primary_user_email, :primary_private_user_email, :stealth_user_email, :profile]
    )
    preloader.call

    history = { commits: {}, additions: {}, deletions: {} }
    users_by_id.each do |_, user|
      next unless email = user.git_author_email
      history[:commits][email] = Hash.new(0)
      history[:additions][email] = {}
      history[:deletions][email] = {}
    end

    summaries = for_repository(repository).for_user(users)

    ContributionIterator.new(summaries).each_with_object(history) do |contribution, history|
      next unless user = users_by_id[contribution.user_id]
      next unless email = user.git_author_email

      timestamp = contribution.committed_date.to_time.to_i
      history[:commits][email][timestamp] = contribution.commit_count
      history[:additions][email][timestamp] = 0
      history[:deletions][email][timestamp] = 0
    end
  end

  # Public: Generate commit activity history for the given repository
  #
  # repository - The Repository to generate the commit activity for.
  #
  # Returns a Hash of [[timestamp => count, ...]] in the same format as returned by
  # GitHub::RepoGraph::ContributionInsights#fetch_commit_activity_data.
  def self.repository_commit_activity(repository:)
    date_range = Range.new(1.year.ago, nil)

    # Aggregate counts for days in range from each summary for a given year
    summaries = CommitContributionSummary.for_repository(repository).covering_date_range(date_range)
    counts_by_day = ContributionIterator.new(summaries, date_range).each_with_object(Hash.new(0)) do |contribution, counts|
      counts[contribution.committed_date] += contribution.commit_count
    end

    # Return days with commits, sorted by timestamp
    counts_by_day.sort_by(&:first).map do |date, count|
      [date.to_time.to_i, count]
    end
  end

  # Synthesize CommitContribution objects that represent contribution detail for the given user
  # and optional list of repositories over the given date range.
  #
  # date_range - A Range of Date objects to generate contributions for.
  # user - The User to generate contributions for.
  # repositories - An optional Array of Repository objects to generate contributions for, if no
  #                repositories are provided, contributions for all repositories will be included.
  #
  # Returns an Array of unpersisted CommitContribution objects.
  def self.commit_contributions_for(date_range:, user:, repositories:)
    summaries = for_user(user).covering_date_range(date_range).includes(:repository)
    summaries = summaries.where(repository: repositories) if repositories
    summaries = summaries.includes(:repository, :user)

    ContributionIterator.new(summaries, date_range).map do |contribution|
      CommitContribution.new(
        user: user,
        repository: contribution.repository,
        committed_date: contribution.committed_date,
        commit_count: contribution.commit_count
      )
    end
  end

  # Public: Get a list of User IDs of top contributors to a repository
  #
  # repository: the Repository to get contributors for
  # limit: how many users to return at most
  #
  # Returns an Array of Integer User IDs
  sig { params(repository: Repository, limit: Integer).returns(T::Array[Integer]) }
  def self.top_repository_contributor_ids(repository:, limit:)
    ActiveRecord::Base.connected_to(role: :reading) do
      scope = CommitContributionSummary.for_repository(repository).group(:user_id).no_ghost_users.
        order(Arel.sql("SUM(total_count) DESC"), :user_id)
      scope.limit(limit).pluck(:user_id)
    end
  end

  # Public: Find the repository IDs that the given user has contributed to, optionally
  # after a given date.
  #
  # user - The User to find contributed repositories for.
  # since - An optional Date, if provided only repositories that the user has contributed
  #         to after the given date will be included.
  # prior_to - An optional Date, if provided only repositories that the user has contributed
  #         to before the given date will be included.
  #
  # Returns an Array of Integer repository IDs.
  sig do
    params(
      user: User,
      since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
      prior_to: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))
    ).returns(T::Array[Integer])
  end
  def self.contributed_repo_ids(user:, since:, prior_to:)
    return for_user(user).distinct.pluck(:repository_id) if since.nil? && prior_to.nil?

    date_range = if since && prior_to
      since..prior_to
    elsif since
      since..Date.today
    elsif prior_to
      Range.new(nil, prior_to)
    end
    summaries = for_user(user)
    summaries = summaries.covering_date_range(date_range) if date_range

    summaries.group_by(&:repository_id).filter_map do |repository_id, summaries|
      repository_id if ContributionIterator.new(summaries, date_range).any?
    end
  end

  # Public: Find the top repository IDs that the given user has contributed to, optionally
  # after a given date.
  #
  # user - The User to find contributed repositories for.
  # limit: the number of top repository IDs to return
  # repository_ids: optional list of repository IDs to consider
  #
  # Returns an Array of Integer Repository IDs
  sig { params(user: User, limit: Integer, repository_ids: T.nilable(T::Array[Integer])).returns(T::Array[Integer]) }
  def self.top_contributed_repository_ids(user:, limit:, repository_ids:)
    date_range = Range.new(1.year.ago, nil)

    summaries = for_user(user).covering_date_range(date_range)
    summaries = summaries.for_repository(repository_ids) if repository_ids&.any?
    counts_by_repo_id = ContributionIterator.new(summaries, date_range).each_with_object(Hash.new(0)) do |contribution, counts|
      counts[contribution.repository_id] += contribution.commit_count
    end

    counts_by_repo_id.sort_by(&:last).reverse.map(&:first).first(limit)
  end

  # Public: Find the user IDs that have contributed to the given repository, optionally
  # after a given date.
  #
  # repository - The Repository to find contributors for.
  # users - An optional Array of User objects to include in the results
  # since - An optional Date, if provided only users that have contributed to the
  #         repository between the given date and today will be included.
  # exclude_ghost: Whether to exclude the Ghost user, optional defaults to false.
  #
  # Returns an Array of Integer user IDs.
  sig do
    params(
      repository: Repository,
      users: T::Array[User],
      since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone)),
      exclude_ghost: T.nilable(T::Boolean)
    ).returns(T::Array[Integer])
  end
  def self.contributed_user_ids(repository:, users: [], since: nil, exclude_ghost: false)
    scope = for_repository(repository)
    scope = scope.no_ghost_users if exclude_ghost
    scope = scope.for_user(users) if users.any?

    return scope.distinct.pluck(:user_id) if since.nil?

    date_range = since..Date.today

    summaries = scope.covering_date_range(date_range)
    summaries.group_by(&:user_id).filter_map do |user_id, summaries|
      user_id if ContributionIterator.new(summaries, date_range).any?
    end
  end

  # Public: Determine if the given repositories have had contributions since the given date.
  #
  # repository_ids - An Array of Integer repository IDs to check for contributions.
  # since - A Date, only contributions after the given date will be considered.
  #
  # Returns a Boolean.
  def self.has_recent_contributions?(repository_ids:, since:)
    date_range = since..Date.today

    summaries = for_repository(repository_ids).covering_date_range(date_range).order(updated_at: :desc).to_a

    ContributionIterator.new(summaries, date_range).any?
  end

  # Public: Get the first recorded commit contribution date for a given repository
  #
  # repository: the Repository to get the date for
  #
  # Returns a Date
  sig { params(repository: Repository).returns(T.nilable(Date)) }
  def self.first_repository_contribution_date(repository:)
    # We need to check all summaries from the first year they exist for this repo. In general, the earliest
    # created summary will have the earliest commit day, so we check them in that order.
    first_year = CommitContributionSummary.for_repository(repository).minimum(:year)
    summaries = CommitContributionSummary.for_repository(repository).where(year: first_year).order(:created_at).to_a
    return nil if summaries.empty?

    first_contribution_index = summaries.minimum(:first_nonzero_index)

    Date.new(first_year, 1, 1) + first_contribution_index.days
  end

  # Public: Find the number of days the given user has contributed to each repository
  # after a given date.
  #
  # user - The User to find contributed repositories for.
  # since - Date to check for contributions since
  #
  # Returns a hash of repository ID to Integer day count.
  sig { params(user: User, since: T.any(Date, DateTime, ActiveSupport::TimeWithZone)).returns(T::Hash[Integer, Integer]) }
  def self.days_with_commits_count_by_repo(user:, since:)
    date_range = Range.new(since, nil)
    summaries = for_user(user).covering_date_range(date_range)
    ContributionIterator.new(summaries, date_range).each_with_object(Hash.new(0)) do |contribution, counts_by_repo|
      counts_by_repo[contribution.repository_id] += 1
    end
  end

  # Public: Count of distinct contributors to a given repository
  #
  # repository – The repository to get the commit contribution count from
  #
  # Returns an Integer count.
  sig { params(repository: Repository, since: T.nilable(T.any(Date, DateTime, ActiveSupport::TimeWithZone))).returns(Integer) }
  def self.contributors_count_for_repository(repository, since:)
    ActiveRecord::Base.connected_to(role: :reading) do
      if since.nil?
        CommitContributionSummary.for_repository(repository).no_ghost_users.distinct.count(:user_id)
      else
        date_range = Range.new(since, nil)
        summaries = CommitContributionSummary.for_repository(repository).no_ghost_users.covering_date_range(date_range)
        summaries.group_by(&:user_id).filter_map do |user_id, summaries|
          user_id if ContributionIterator.new(summaries, date_range).any?
        end.count
      end
    end
  end

  # Find the most recent date the given user has contributed to the given repository,
  # optionally after a given date.
  #
  # user - The User to find the last contribution date for.
  # repository - The Repository to find the last contribution date for.
  #
  # Returns a Date object, or nil if no matching contribution was found.
  sig do
    params(
      user: User,
      repository: Repository,
    ).returns(T.nilable(Date))
  end
  def self.last_contribution_date(user:, repository:)
    return nil unless summary = for_user(user).for_repository(repository).order(year: :desc).first
    Date.new(summary.year, 1, 1) + summary.last_nonzero_index.days
  end

  # Public: Find the earliest day a given user has contributed to any repository.
  #
  # user: the User to check
  #
  # Returns a Date or nil
  sig { params(user: User).returns(T.nilable(Date)) }
  def self.first_contribution_date(user:)
    return nil unless first_contribution_year = for_user(user).minimum(:year)
    first_contribution_index = for_user(user).where(year: first_contribution_year).to_a.minimum(:first_nonzero_index)
    Date.new(first_contribution_year, 1, 1) + first_contribution_index.days if first_contribution_index
  end

  # Public: User IDs who have contributed to a given repository, sorted by most recent to least recent contribution date.
  #
  # repository - The Repository to find contributors for.
  # limit - The maximum number of user IDs to return.
  #
  # Returns an Array of Integer user IDs.
  sig do
    params(
      repository: Repository,
      limit: Integer,
    ).returns(T::Array[Integer])
  end
  def self.contributed_user_ids_by_recency(repository:, limit:)
    ghost_id = User.ghost.id

    sorted_user_ids = []
    already_processed_users = Set.new

    contribution_years = for_repository(repository).distinct.order(year: :desc).pluck(:year)

    # Process contributors one year at a time to reduce time spent unpacking and processing
    # counts. If we didn't find enough contributors in a given year, we go back a year and keep
    # looking for more contributors.
    #
    # This should improve performance for repositories with a large number of contributors and a
    # long contribution history. Other repositories should be faster because there are fewer
    # summaries to check.
    contribution_years.each do |year|
      year_summaries = for_repository(repository).where(year: year)

      # Sort this year's summaries by recency
      sorted_year_summaries = year_summaries.sort_by(&:last_nonzero_index).reverse

      # Add new user IDs from this years summaries until we hit the limit
      sorted_year_summaries.each do |summary|
        next if summary.user_id == ghost_id
        next if already_processed_users.include?(summary.user_id)
        already_processed_users << summary.user_id
        sorted_user_ids << summary.user_id
        break if sorted_user_ids.size >= limit
      end

      break if sorted_user_ids.size >= limit
    end

    sorted_user_ids
  end

  private

  # Private: Set the total contribution count to the sum of all weekly counts.
  #
  # Returns the updated Integer total contribution count.
  def update_total_count
    assign_attributes(total_count: counts.sum)
  end

  # Private: Ensure all values are Integers, eg. in cases where a new summary
  # record was populated with sparse values, so nils are converted to zeros.
  #
  # This also pads short arrays to have the correct number of values.
  def normalize_counts
    self.counts ||= []
    dates_in_year.each { |date| self.counts[date.yday - 1] ||= 0 }
  end

  # Private: Validate that there is at least one contribution during the year.
  def has_at_least_one_contribution
    if counts.all?(&:zero?)
      errors.add(:counts, "must have at least one contribution during the year")
    end
  end

  # Private: The range of dates in the summary year
  #
  # Returns a Range of Date objects.
  def dates_in_year
    Date.new(year, 1, 1)..Date.new(year, 12, 31)
  end
end
