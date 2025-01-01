# typed: true
# frozen_string_literal: true

module Repository::StarsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  CACHE_TIME_FORMAT = "%Y-%m-%e"
  DATE_OPTIONS = {
    daily: { text: "today", period: 1.day },
    weekly: { text: "this week", period: 7.days },
    monthly: { text: "this month", period: 1.month },
  }.freeze

  # Public: Name of the database field used to store the repository's star count.
  # Overridden from Starrable.
  #
  # Returns a String.
  def stargazer_count_column
    T.cast(self.class, T.class_of(Repository)).stargazer_count_column # rubocop:todo GitHub/AvoidCast
  end

  # Ensures that people who starred the repository are people who are allowed
  # to star it. Useful for private repositories and transferring between
  # owners who may change who has access to the repository (collabs -> teams).
  #
  # Returns nothing.
  def correct_stargazers
    return if self.public?
    stargazer_ids = Star.where(starrable_id: id, starrable_type: "Repository").pluck(:user_id)

    stargazer_ids.each_slice(Repository::REPO_STARGAZERS_BATCH_SIZE) do |stargazer_ids_slice|
      stargazers = User.where(id: stargazer_ids_slice)

      Promise.all(stargazers.map do |user|
        self.async_readable_by?(user).then do |readable|
          user.unstar(self) unless readable
        end
      end).sync
    end
  end

  # Public: Calculate how many non-spammy users have starred this repository.
  #
  # Returns an Integer.
  def calculate_stargazer_count
    ActiveRecord::Base.connected_to(role: :reading) do
      stars.not_spammy.count
    end
  end

  # Public: Update the memoization field on this repository with the latest count of how many users have starred it.
  #
  # count - optional Integer count of how many users have starred this repo; defaults to #calculate_stargazer_count
  #
  # Returns nothing.
  def update_stargazer_count!(count: calculate_stargazer_count)
    if count != stargazer_count
      update_attribute :stargazer_count, count
    end
  end

  # Public: Returns the amount of stars that a repository has obtained since
  # the given time period. Default time period is the last day.
  def stars_since(period: :daily)
    cache_key = stars_since_cache_key(period: period)
    stars = GitHub.kv.get(cache_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    if stars.blank?
      stars = self.stars.where(["created_at > ?", created_at_starting_date_for(period: period)]).size
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.kv.set(cache_key, stars.to_s, expires: cache_expiry_time(period)) # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end
    stars.to_i
  end

  def stars_since_cache_key(period: :daily)
    cache_key_time = DateTime.current.strftime(CACHE_TIME_FORMAT)
    cache_key = ["stars_since", period, "repository", id, cache_key_time].join(".")
  end

  private

  def cache_expiry_time(period)
    DATE_OPTIONS[period][:period].from_now
  end

  def created_at_starting_date_for(period:)
    fallback_option = DATE_OPTIONS[:daily]

    DATE_OPTIONS.fetch(period, fallback_option)[:period].ago
  end
end
