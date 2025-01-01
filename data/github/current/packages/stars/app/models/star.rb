# typed: true
# frozen_string_literal: true

class Star < ApplicationRecord::Mysql1
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include Spam::Spammable
  include Starlike
  extend GitHub::SimplePagination

  STARRABLE_TYPE_GIST = "Gist".freeze
  STARRABLE_TYPE_REPOSITORY = "Repository".freeze
  STARRABLE_TYPE_TOPIC = "Topic".freeze

  STARRABLE_TYPES = [
    STARRABLE_TYPE_GIST,
    STARRABLE_TYPE_REPOSITORY,
    STARRABLE_TYPE_TOPIC,
  ].freeze

  # Filtering too many starred repositories can choke MySQL/ES
  STARRED_REPOSITORY_LIMIT = 25_000

  # Locations on the site that we show the Star/Unstar buttons. Corresponds to the ContextType enum in Hydro for
  # the entity being starred:
  # - https://github.com/github/hydro-schemas/blob/0738d0c5747072c2e4d22e83072615a162f15fab/proto/hydro/schemas/github/v1/repository_star.proto#L41
  # - https://github.com/github/hydro-schemas/blob/9f94d5dca47d467c9aa73e0400799f3c459ed91a/proto/hydro/schemas/github/v1/gist_star.proto#L40
  # - https://github.com/github/hydro-schemas/blob/0738d0c5747072c2e4d22e83072615a162f15fab/proto/hydro/schemas/github/v1/topic_star.proto#L38
  STARRABLE_CONTEXTS = %w[collections trending repository repo_stargazers user_stars gist user_list
                          discovery_feed api news_feed topic context_type_unknown other recovery].freeze

  class << self
    attr_accessor :per_page
  end
  self.per_page = 30

  after_create :reindex_starrable_for_search
  after_commit :instrument_create, on: :create # keep before `increment_starrable_stargazer_count` callback
  after_commit :increment_starrable_stargazer_count, on: :create
  after_commit :remove_starrable_from_user_lists, on: :destroy
  after_commit :instrument_destroy, on: :destroy # keep before `decrement_starrable_stargazer_count` callback
  after_commit :decrement_starrable_stargazer_count, on: :destroy
  after_commit :reindex_starrable_for_search, on: :destroy
  after_commit :reindex_stars_for_repository_actions

  belongs_to :user
  belongs_to :starrable, polymorphic: true
  delete_in_background_with :starrable, polymorphic_class_name: "Repository"

  setup_spammable(:user)

  validates_presence_of :user
  validates_presence_of :starrable_id, :starrable_type

  validates :starrable_type, inclusion: { in: STARRABLE_TYPES }
  validate :validate_star_is_authorized, on: :create

  scope :newest, -> { order("created_at DESC") }
  scope :repositories, -> { where(starrable_type: STARRABLE_TYPE_REPOSITORY) }
  scope :topics, -> { where(starrable_type: STARRABLE_TYPE_TOPIC) }
  scope :since, -> (date) { where("stars.created_at >= ?", date) }
  scope :for_repository, ->(repo_id) { repositories.where(starrable_id: repo_id) }
  scope :for_topic, ->(topic_id) { topics.where(starrable_id: topic_id) }

  # Public: Get the IDs of repositories the given user has starred, from a list of repository IDs to check.
  #
  # user - a User
  # repository_ids - an Array of Repository IDs to check star status
  #
  # Returns a Set of Repository IDs.
  def self.starred_repository_ids_from(user:, repository_ids:)
    Set.new(user.stars.for_repository(repository_ids).pluck(:starrable_id))
  end

  # Public: Get the stars of repositories the given user has starred, from a list of repository IDs to check.
  #
  # user - a User
  # repository_ids - an Array of Repository IDs to check star status
  #
  # Returns an AR scope of stars
  def self.stars_for_user_and_repos(user_id:, repository_ids:)
    Star.where(user_id: user_id, starrable_id: repository_ids, starrable_type: "Repository")
  end

  # Find the most starred repositories based on who the user follows
  #
  # user           - required, the user who we're looking up their followings
  # period         - daily, weekly, monthly. the time period to look for the stars
  # limit          - how many results to return
  # include_topics - a Boolean indicating if starred Topics should be included
  #                  in the results.
  #
  # Returns Array of Stars
  def self.from_following(user, options = {})
    period = options[:period] || "daily"
    limit = options[:limit] || 25
    include_topics = options[:include_topics].nil? ? true : options[:include_topics]

    following_ids = user.following_ids
    return [] if following_ids.empty?

    repos = ActiveRecord::Base.connected_to(role: :reading) do
      repo_sql_bindings = {
        following_ids: following_ids,
        since: timestamp_for_period(period),
        exclude_repos: options[:exclude_repos],
      }

      repo_sql = Arel.sql <<~SQL, **repo_sql_bindings
        SELECT COUNT(starrable_id) AS friend_count, starrable_id, starrable_type
        FROM stars
        WHERE user_id IN (:following_ids)
          AND created_at BETWEEN :since AND NOW()
          AND starrable_type = 'Repository'
          #{ "AND starrable_id NOT IN (:exclude_repos)" if options[:exclude_repos].present? }
        GROUP BY starrable_type, starrable_id
        ORDER BY friend_count DESC, starrable_id
        LIMIT 1000
      SQL

      rows = self.connection.select_all(repo_sql).to_a

      repository_ids = rows.map { |row| row["starrable_id"] }
      public_repo_ids = Repository.public_scope.where(id: repository_ids).ids.to_set

      rows.select! { |row| public_repo_ids.include?(row["starrable_id"]) }
      rows.first(limit).map { |row| Star.instantiate(row) }
    end

    topics = if include_topics
      ActiveRecord::Base.connected_to(role: :reading) do
        topic_sql_bindings = {
          user_id: user.id,
          limit: Arel.sql(limit.to_s),
          since: timestamp_for_period(period),
          exclude_topics: options[:exclude_topics],
          user_ids: following_ids,
        }

        topic_sql = Arel.sql <<~SQL, **topic_sql_bindings
          SELECT COUNT(starrable_id) AS friend_count, starrable_id, starrable_type
          FROM stars
          WHERE user_id IN (:user_ids)
            AND created_at BETWEEN :since AND NOW()
            AND starrable_type = 'Topic'
            #{ "AND starrable_id NOT IN (:exclude_topics)" if options[:exclude_topics].present? }
          GROUP BY starrable_type, starrable_id
          ORDER BY friend_count DESC, starrable_id
          LIMIT :limit
        SQL

        self.find_by_sql(topic_sql)
      end
    else
      Topic.none
    end

    # sort by stargazer_count, with a secondary ordering to keep results consistent
    (repos + topics).sort_by { |star| [star.starrable.stargazer_count, star.starrable_id] }.first(limit)
  end

  # Picks the date range for star queries.
  #
  # period - The time period to go back until (required)
  #
  # Returns ActiveSupport::TimeWithZone
  def self.timestamp_for_period(period)
    case period.to_s
    when "weekly" then 1.week.ago
    when "monthly" then 1.month.ago
    else 1.day.ago
    end
  end

  def for_topic?
    starrable.is_a?(Topic)
  end

  def for_repository?
    starrable.is_a?(Repository)
  end

  def public_starrable?
    return false unless starrable

    starrable.public?
  end

  def event_context(prefix: :starred)
    {
      prefix                  => (starrable.kind_of?(Repository) ? starrable.nwo : starrable.to_s),
      "#{prefix}_type".to_sym => starrable_type,
      "#{prefix}_id".to_sym   => starrable_id,
    }
  end

  # Public: Forces an index
  #
  # index - the index to suggest
  #
  # Returns nothing.
  def self.force_index(index)
    from("#{self.table_name} FORCE INDEX(#{index})")
  end

  private

  def increment_starrable_stargazer_count
    modify_starrable_stargazer_count(increment: true)
  end

  def decrement_starrable_stargazer_count
    modify_starrable_stargazer_count(increment: false)
  end

  def modify_starrable_stargazer_count(increment:)
    return unless starrable && starrable.stargazer_count_column

    change_count = !GitHub.spamminess_check_enabled? || (user && !user&.spammy?)
    return unless change_count

    starrable.modify_stargazer_count(increment: increment)
  end

  def event_payload
    {
      starred:    self,
      user:       user,
      spammy:     user&.spammy?,
      allowed:    allowed?,
      star_id:    self.id,
      context:    hydro_context_type,
    }.tap do |p|
      p[:public_repo] = starrable.public? if starrable.kind_of?(Repository)
    end
  end

  def allowed?
    !!starrable.try(:permit?, user, :write)
  end

  def instrument_create
    # Audit log
    instrument(:create, action: :created)

    # Hydro
    GlobalInstrumenter.instrument("user.star",
      hydro_attributes_for(entity: starrable, actor: actor, context: hydro_context_type))
  end

  def instrument_destroy
    # Audit log
    instrument(:destroy, action: :deleted)

    # Hydro
    GlobalInstrumenter.instrument("user.unstar",
      hydro_attributes_for(entity: starrable, actor: actor, context: hydro_context_type))
  end

  def remove_starrable_from_user_lists
    return unless (starrable_type == STARRABLE_TYPE_REPOSITORY) && starrable.present?

    if user&.has_list_with_item?(starrable)
      UserList.replace_all(user_id: user&.id, repository_id: starrable.id, list_ids: [])
    end
  end

  def validate_star_is_authorized
    authorization = ContentAuthorizer.authorize(user, :star, :create, starrable: starrable)

    if authorization.failed?
      errors.add(:base, authorization.error_messages)
    end
  end

  def reindex_starrable_for_search
    return unless starrable.respond_to?(:synchronize_search_index)
    starrable.synchronize_search_index
  end

  def reindex_stars_for_repository_actions
    return unless starrable.respond_to?(:synchronize_repository_actions_search_index)
    starrable.synchronize_repository_actions_search_index
  end
end
