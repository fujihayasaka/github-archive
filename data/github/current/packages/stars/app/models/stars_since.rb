# typed: strict
# frozen_string_literal: true

class StarsSince
  Period = T.type_alias { T::Hash[Symbol, T.any(String, Date)] }
  CACHE_TIME_FORMAT = "%Y-%m-%e"
  DATE_OPTIONS = T.let({
    daily: { text: "today", period: 1.day },
    weekly: { text: "this week", period: 7.days },
    monthly: { text: "this month", period: 1.month },
  }.freeze, T::Hash[Symbol, Period])

  sig { params(repository_id: Integer, period: Symbol).returns(Integer) }
  def self.repository(repository_id:, period: :daily)
    new.repository(repository_id:, period:)
  end

  sig { params(repository_id: Integer, period: Symbol).returns(Integer) }
  def repository(repository_id:, period: :daily)
    T.must(get_multiple(repository_ids: [repository_id], period:)[repository_id])
  end

  sig { params(repository_ids: T::Array[Integer], period: Symbol).returns(T::Hash[Integer, Integer]) }
  def self.repositories(repository_ids:, period: :daily)
    new.repositories(repository_ids:, period:)
  end

  sig { params(repository_ids: T::Array[Integer], period: Symbol).returns(T::Hash[Integer, Integer]) }
  def repositories(repository_ids:, period: :daily)
    get_multiple(repository_ids:, period:)
  end

  private

  sig { params(repository_ids: T::Array[Integer], period: Symbol).returns(T::Hash[Integer, Integer]) }
  def get_multiple(repository_ids:, period:)
    cache_keys = repository_ids.map { |repository_id| stars_since_cache_key(repository_id:, period:) }
    values = Stars::Kv.store.mget(cache_keys).value { [] }
    counts = repository_ids.zip(values)
    missing = counts.select { |_, value| value.blank? }.map(&:first)
    updated = set_multiple(repository_ids: missing, period:)

    counts.to_h.merge(updated).transform_values(&:to_i)
  end

  sig { params(repository_ids: T::Array[Integer], period: Symbol).returns(T::Hash[Integer, Integer]) }
  def set_multiple(repository_ids:, period:)
    return {} if repository_ids.empty?

    counts = Star.repositories
      .where(starrable_id: repository_ids)
      .where(["created_at > ?", created_at_starting_date_for(period:)])
      .group(:starrable_id)
      .count

    stars = repository_ids.map { |repository_id| [repository_id, (counts[repository_id] || 0).to_s] }.to_h
    updates = stars.transform_keys { |repository_id| stars_since_cache_key(repository_id:, period:) }

    ActiveRecord::Base.connected_to(role: :writing) do
      Stars::Kv.store.mset(updates, expires: cache_expiry_time(period))
    end

    stars
  end

  sig { params(repository_id: Integer, period: Symbol).returns(String) }
  def stars_since_cache_key(repository_id:, period: :daily)
    cache_key_time = DateTime.current.strftime(CACHE_TIME_FORMAT)
    cache_key = ["stars_since", period, "repository", repository_id, cache_key_time].join(".")
  end

  sig { params(period: Symbol).returns(ActiveSupport::Duration) }
  def duration(period)
    raise ArgumentError, "Invalid period" unless DATE_OPTIONS.key?(period)

    T.cast(T.must(DATE_OPTIONS[period])[:period], ActiveSupport::Duration)
  end

  sig { params(period: Symbol).returns(ActiveSupport::TimeWithZone) }
  def cache_expiry_time(period)
    duration(period).from_now
  end

  sig { params(period: Symbol).returns(ActiveSupport::TimeWithZone) }
  def created_at_starting_date_for(period:)
    duration(period).ago
  end
end
