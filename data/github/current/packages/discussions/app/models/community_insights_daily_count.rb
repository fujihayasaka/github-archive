# typed: true
# frozen_string_literal: true

class CommunityInsightsDailyCount < ApplicationRecord::Domain::RepositoriesCollab
  PERIODS = {
    last_30_days: 30.days,
    last_3_months: 90.days,
    last_year: 365.days,
  }.freeze

  PERIOD_SPLIT_SIZES = {
    # these numbers were chosen to leave no remainder when dividing the periods
    last_30_days: 6,
    last_3_months: 30,
    last_year: 73
  }.freeze

  INCREMENTABLE_ATTRIBUTES = %i(
    discussions_count issues_count pull_requests_count discussion_contributors_count discussion_new_contributor_count
    discussion_logged_in_page_view_count discussion_anonymous_page_view_count
  ).freeze

  belongs_to :repository

  validates :repository_id, :entry_date, presence: true
  validate :ensure_at_least_one_nonzero

  sig { params(period: T.untyped).returns(T.untyped) }
  def self.human_period(period = :last_30_days)
    CommunityInsightsDailyCount::PERIODS[period_for(period)]
  end

  sig { returns(T.untyped) }
  def self.default_period
    :last_30_days
  end

  sig { params(period: T.untyped).returns(T.untyped) }
  def self.period_for(period)
    return default_period if period.nil?
    period  = period.to_sym
    PERIODS.has_key?(period) ? period : default_period
  end

  # Public: Record a countable event for a repository at a given date.
  #
  # repository_id - Integer ID for the repository in which the event occurred. Provided as an ID instead of a record
  #   so we can avoid loading a database if we already have the ID.
  # entry_date - The Date on which the event occurred.
  # count_attr - Symbol representing the count field to increment for this attribute.
  #              One of `INCREMENTABLE_ATTRIBUTES`.
  #
  # Returns nothing.
  sig { params(repository_id: T.untyped, entry_date: T.untyped, count_attr: T.untyped).returns(T.untyped) }
  def self.increment(repository_id, entry_date, count_attr)
    raise "Invalid attribute to increment: #{count_attr}" unless INCREMENTABLE_ATTRIBUTES.include?(count_attr)

    query = <<~SQL
      INSERT INTO #{table_name} (repository_id, entry_date, #{count_attr}, created_at, updated_at)
      VALUES
      (:repository_id, :entry_date, 1, :now, :now)
      ON DUPLICATE KEY
      UPDATE id = id, #{count_attr} = #{count_attr} + 1, updated_at = :now
    SQL
    self.connection.insert(Arel.sql(query, repository_id: repository_id, entry_date: entry_date, now: Time.now.utc))
  end

  # Public: Record an absolute countable value for a repository at a given date.
  #
  # repository_id - Integer ID for the repository in which events occurred.
  # entry_date - The Date on which the counted events occurred.
  # count_attr - The count to increment for this attribute. One of :discussions_count, :issues_count,
  #   :pull_requests_count, :discussion_contributors_count, :discussion_new_contributor_count,
  #   :discussion_logged_in_page_view_count, or :discussion_anonymous_page_view_count.
  # count - Integer count to set this attribute by.
  #
  # Returns the loaded or created record.
  sig do
    params(
      repository_id: T.untyped,
      entry_date: T.untyped,
      count_attr: T.untyped,
      count: T.untyped
    ).returns(T.untyped)
  end
  def self.set_count(repository_id, entry_date, count_attr, count)
    return nil if Repositories::Public.is_deleted?(repository_id)  # This repository has been archived, so don't create a count record.
    retry_on_find_or_create_error do
      model = find_by(repository_id: repository_id, entry_date: entry_date)
      if model
        if !model.update(count_attr => count)
          # This count record is now invalid (e.g. it has all counts of 0). Delete it.
          model.destroy
        end
        model
      elsif count > 0
        create!({ :repository_id => repository_id, :entry_date => entry_date, count_attr => count })
      end
    end
  end

  # Retrieve the collection of counts for a given repository and period. These count records provide all of the
  # information needed to generate the graphs on the Community Insights page.
  #
  # repository - The Repository to retrieve counts for.
  # period - The period to retrieve counts for. One of :last_30_days, :last_3_months, or :last_year.
  #
  # Returns a Relation of CommunityInsightsDailyCount records, ordered by ascending entry_date.
  sig { params(repository: T.untyped, period: T.untyped).returns(T.untyped) }
  def self.all_for_period(repository, period)
    from_date = Date.today - PERIODS.fetch(period)
    where(repository_id: repository.id, entry_date: from_date..Date.today.end_of_day).order(:entry_date)
  end

  sig { returns(T.untyped) }
  def zero?
    [
      discussions_count,
      issues_count,
      pull_requests_count,
      discussion_contributors_count,
      discussion_new_contributor_count,
      discussion_logged_in_page_view_count,
      discussion_anonymous_page_view_count,
    ].all?(&:zero?)
  end

  private

  def ensure_at_least_one_nonzero
    if zero?
      errors.add(:base, "At least one of the counts must be non-zero")
    end
  end
end
