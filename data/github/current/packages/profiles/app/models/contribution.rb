# typed: true
# frozen_string_literal: true

class Contribution
  extend TimezoneFiltering


  # A limit on how many pull request reviews, issues, and pull requests we bother with. The vast,
  # vast majority of users have far fewer, but bots, like houndci-bot, have a lot.
  # We don't care about bots.
  DEFAULT_COUNT_LIMIT = 10_000

  RETENTION_DURATION = 5.years

  attr_reader :user

  def initialize(user:, subject: nil)
    @user = user
    @subject = subject

    raise ArgumentError, "requires a user" unless user.present?
    raise ArgumentError, "#{user} must be a User" unless user.user?
  end

  def self.retention_period
    start = RETENTION_DURATION.ago.to_date
    start..Date.today
  end

  # Public: the ID of the contribution. This is used by default to compare contributions
  # to determine their chronological order.
  def id
    subject.id
  end

  # Public: whether this contribution was created before the given other contribution.
  #
  # Most contribution collections are ordered by their database ID value; those that use other
  # ordering should override this method.
  #
  # Returns a Boolean.
  def created_before?(other)
    raise ArgumentError, "contribution type mismatch" unless other.is_a?(self.class)
    id < other.id
  end

  def self.fetcher_class
    nil
  end

  def self.measure(metric, tags: [])
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    yield
  ensure
    GitHub.dogstats.distribution(
      "contributions.queries.dist.time",
      GitHub::Dogstats.duration(start),
      tags: ["query:#{metric}"] + tags,
    )
  end

  def <=>(other)
    occurred_at <=> other.occurred_at
  end

  def restricted?
    false
  end

  def contribution_class
    self.class
  end

  # Public: The ID of the repository associated with this contribution. Might be nil.
  #
  # Returns an Integer or nil.
  def repository_id
  end

  # Public: The ID of the organization associated with this contribution. Might be nil.
  #
  # Returns an Integer or nil.
  def organization_id
  end

  # Public: Used to determine if a viewer has access to a contribution. Subclasses
  # should override this method to return one of the following:
  #
  # - Repository instance
  # - Organization instance
  # - User instance
  # - EnterpriseContribution instance
  #
  # Events with a nil associated subject are hidden by default so
  # that newly added contribution types don't accidentally expose private data.
  def associated_subject
    raise NotImplementedError,
      "The #associated_subject method needs to be implemented in #{self.class.name}."
  end

  # Public: Returns the time or date that this contribution occurred. Defined in child
  # classes.
  def occurred_at
    raise NotImplementedError,
        "The #occurred_at method needs to be implemented in #{self.class.name}."
  end

  # Public: Returns the Date when the contribution occurred.
  def occurred_on
    occurred_at.to_date
  end

  # Public: Returns a URL to link to this contribution on a user's profile.
  def url
    month_start = occurred_at.beginning_of_month.strftime("%Y-%m-%d")
    month_end = occurred_at.end_of_month.strftime("%Y-%m-%d")
    "/#{user}?tab=overview&from=#{month_start}&to=#{month_end}"
  end

  # Public: Returns how many contributions this represents. Usually a contribution
  # represents one contribution. But for example the CreatedCommit contribution
  # is based on CommitContribution that aggregates several commits created on
  # a single day.
  #
  # Returns a Integer.
  def contributions_count
    1
  end

  def self.first_subject_for(user, excluded_organization_ids: [])
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    []
  end

  # Public: Clears all cache's related to contributions for the given user. This includes:
  # - Contribution::Collector
  # - Contribution::Calendar
  #
  def self.clear_caches_for_user(user, context: "unknown")
    GitHub.dogstats.increment("contribution.clear_caches_for_user", tags: ["context:#{context}"])
    Contribution::Accessor.clear_cache_for_user(user)
  end

  def self.bulk_clear_caches_for_users(users, context: "unknown")
    GitHub.dogstats.increment("contribution.bulk_clear_caches_for_users", tags: ["context:#{context}"])
    Contribution::Accessor.bulk_clear_cache_for_users(users)
  end

  # Public: Some contributions are fetched by a database timestamp and
  # need to be filtered again by a computed value.
  def self.needs_filtering_by_occurred_at?
    false
  end

  private

  attr_reader :subject
end
