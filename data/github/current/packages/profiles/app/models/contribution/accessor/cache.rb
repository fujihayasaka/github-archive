# typed: true
# frozen_string_literal: true

class Contribution::Accessor::Cache
  CACHE_VERSION = 1

  def self.clear_cache_for_user(user)
    Profiles::Kv.store.del(user_namespace_key(user))
  end

  def self.bulk_clear_cache_for_users(users)
    Profiles::Kv.store.mdel(users.map { |user| user_namespace_key(user) })
  end

  def self.user_namespace(user)
    key = user_namespace_key(user)
    value = Profiles::Kv.store.get(key).value!

    if value.nil?
      value = [user.id, Time.now.to_f.to_s].join(",")
      ActiveRecord::Base.connected_to(role: :writing) { Profiles::Kv.store.set(key, value) }
    end

    value
  end

  def self.user_namespace_key(user)
    "contribs-accessor-ns:#{user.id}"
  end
  private_class_method :user_namespace_key

  def initialize(
    user:,
    viewer:,
    contribution_classes:,
    date_range:,
    organization_id:,
    skip_restricted:,
    excluded_organization_ids:,
    lightweight:
  )
    @user = user
    @viewer = viewer
    @contribution_classes = contribution_classes
    @date_range = date_range
    @organization_id = organization_id
    @skip_restricted = skip_restricted
    @excluded_organization_ids = excluded_organization_ids
    @lightweight = lightweight
  end

  # Public: Set the data to be cached for this accessor
  #
  # data - Hash
  def set(data)
    GitHub.cache.set(key, data)
  end

  # Public: Get the cached accessor data
  #
  # Returns a hash of data, or nil if the data wasn't cached
  def get
    data = GitHub.cache.get(key)
    log_cache_stat(data)

    data
  end

  private

  # Public: Returns a cache key that invalidates when the following changes:
  #   - mass-invalided by bumping the Cache::CACHE_VERSION
  #   - invalidated in stafftools (see: Cache.user_namespace)
  #   - date range
  #   - contribution classes
  #   - viewer_id
  #   - org is specified
  # Returns a String
  def key
    return @key if defined? @key

    @user_namespace ||= self.class.user_namespace(@user)

    key_data = [
      CACHE_VERSION,
      @user_namespace,
      @contribution_classes.map(&:name).sort.join(","),
      @date_range.begin,
      @date_range.end,
      @viewer&.id,
      @organization_id,
      !!@skip_restricted,
      @excluded_organization_ids.sort.join(","),
      @lightweight,
    ]

    @key = "accessor-cache:#{Digest::SHA256.hexdigest(key_data.join(":"))}"
  end

  def log_cache_stat(data)
    days_in_year = @date_range.begin.end_of_year.yday # Number of days in the year
    is_year_long = @date_range.count >= days_in_year
    includes_today = @date_range.cover?(Date.current)

    tags = [
      "action:contributions.accessor",
      "logged_in:#{@viewer.present?}",
      "is_year_long:#{is_year_long}",
      "includes_today:#{includes_today}",
    ]
    GitHub.dogstats.increment(data ? "cache.hit" : "cache.miss", tags: tags)
  end
end
