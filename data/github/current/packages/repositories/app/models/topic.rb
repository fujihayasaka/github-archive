# typed: true
# frozen_string_literal: true

require "github/sql/readonly"

class Topic < ApplicationRecord::Domain::Topics
  include ActionView::Helpers::DateHelper
  include GitHub::Validations
  include Instrumentation::Model
  include GitHub::ColumnCount

  NUMBER_OF_FEATURED_TOPICS = 3
  NUMBER_OF_POPULAR_TOPICS = 10
  MAX_NAME_LENGTH = 50
  MAX_SHORT_DESCRIPTION_LENGTH = 255
  MAX_CREATED_BY_LENGTH = 100
  MAX_DISPLAY_NAME_LENGTH = 50
  MAX_RELEASED_LENGTH = 25
  PUBLIC_REPO_COUNT_MAX = 10000
  NAME_REGEX = /\A[a-z0-9][a-z0-9-]*\Z/
  ALIAS_DELIMITER = ","
  RELATED_DELIMITER = ","
  URL_REGEX = %r{\Ahttps?://}.freeze
  CURATED_FIELDS = %i(description short_description created_by display_name logo_url released
                      url wikipedia_url github_url).freeze

  cattr_accessor :per_page, default: 30

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH },
    format: {
      with: NAME_REGEX,
      message: "can only include lowercase letters, numbers, and hyphens, e.g., node-js-6-3-1",
    }
  validates :name, uniqueness: { case_sensitive: false }, if: -> do
    T.bind(self, Topic)

    errors[:name].blank?
  end

  validates :github_url, :url, :wikipedia_url, format: URL_REGEX, allow_nil: true, allow_blank: true

  validates :short_description, length: { maximum: MAX_SHORT_DESCRIPTION_LENGTH }, unicode3: true
  validates :created_by, length: { maximum: MAX_CREATED_BY_LENGTH }, unicode3: true
  validates :display_name, length: { maximum: MAX_DISPLAY_NAME_LENGTH }, unicode3: true
  validates :released, length: { maximum: MAX_RELEASED_LENGTH }, unicode3: true

  before_validation :normalize_name

  has_many :repository_topics, dependent: :destroy
  has_many :topic_relations, dependent: :destroy

  has_many :sources, inverse_of: :topic, class_name: "TopicSource", foreign_key: :topic_id

  has_many :topic_aliases,
    -> { merge(TopicRelation.alias) },
    class_name: "TopicRelation"
  has_many :related_topics,
    -> { merge(TopicRelation.related) },
    class_name: "TopicRelation"
  has_many :applied_repository_topics,
    -> { where state: RepositoryTopic.applied_state_values },
    class_name: "RepositoryTopic"

  # Includes only Repositories that have the Topic applied to them, not those for which
  # the Topic was rejected.
  has_many :repositories, through: :applied_repository_topics, source: :repository

  after_commit :instrument_flag_unflag, only: [:update] # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Includes only Topics that users manually applied to repositories, or topics users
  # accepted from suggestions for their repositories.
  #
  # Note that `applied_count` is updated periodically in a timed background job. See
  # Topic.update_applied_counts and CalculateTopicAppliedCountsJob for more details.
  scope :applied, -> { where.not(applied_count: 0) }

  # Includes Topics that are featured, ones we want to show off.
  scope :featured, -> { where(featured: true) }

  # Includes Topics that are not featured.
  scope :non_featured, -> { where(featured: false) }

  # Includes Topics for which we have curated content.
  scope :curated, -> {
    where("topics.short_description IS NOT NULL AND topics.short_description <> ?", "")
  }

  # Includes only Topics that have been flagged as questionable content.
  scope :flagged, -> { where(flagged: true) }

  # Includes only Topics that have not been flagged as questionable content.
  scope :not_flagged, -> { where(flagged: false) }

  # Orders the topics by recency
  scope :newest_first, -> { order("topics.id DESC") }

  # Includes only Topics that have an image.
  scope :with_logo, -> { where(has_logo_url: true) }

  # Returns the most-used topics that are among the latest to be applied to a public repository.
  scope :popular_on_public_repositories, ->(limit) {
    topic_ids = ::RepositoryTopic.applied.on_public_repositories.newest_first.limit(1_000).
      pluck(:topic_id)

    topic_counts = Hash.new(0)
    topic_ids.each { |id| topic_counts[id] += 1 }

    sorted_topic_counts = topic_counts.sort_by { |_topic_id, count| count }.reverse.to_h
    popular_topic_ids = sorted_topic_counts.keys[0...limit]

    where(id: popular_topic_ids)
  }

  scope :with_name_like, ->(query) {
    # Can only search for valid values
    return none unless GitHub::UTF8.valid_unicode3?(query)

    sanitized_query = "#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    where("topics.name LIKE ?", sanitized_query)
  }

  scope :name_includes, ->(query) {
    # Can only search for valid values
    return none unless GitHub::UTF8.valid_unicode3?(query)

    sanitized_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    where("topics.name LIKE ?", sanitized_query)
  }

  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  extend GitHub::Encoding
  force_utf8_encoding :description

  def to_s
    name
  end

  def to_param
    name
  end

  def stargazer_count_column
    "stargazer_count"
  end

  def modify_stargazer_count(increment:)
    update_column_count(increment:, column_name: stargazer_count_column)
  end

  # Public: Ensure many topics with the specified names exist.
  #
  # valid_topic_names - an Array of valid String topic names
  #
  # Returns an Array of persisted Topic records.
  def self.ensure_names_exist(valid_topic_names)
    return [] if valid_topic_names.empty?

    topics = ActiveRecord::Base.connected_to(role: :reading) do
      Topic.where(name: valid_topic_names).to_a
    end

    missing_names = valid_topic_names - topics.map(&:name)

    if missing_names.any?
      Topic.insert_all(missing_names.map { |name| { name: name } })
      topics += Topic.where(name: missing_names).to_a
    end

    topics
  end

  # Public: Updates the `topics.applied_count` column for Topic records with the given ids.
  #
  # The `applied_count` column is a denormalization of `repository_topics.topic_id` where the
  # `repository_topics` row would be considered "applied."
  #
  # This denormalized value is used in various Topic queries for selection and ordering, such
  # as in autocomplete suggestions.
  #
  # ids - Array of record ids for the rows that should be updated.
  #
  # Returns nothing.
  def self.update_applied_counts(ids)
    return if ids.empty?

    counts_by_ids = T.let({}, T::Hash[Integer, Integer])

    ActiveRecord::Base.connected_to(role: :reading) do
      counts_by_ids = RepositoryTopic.applied.group(:topic_id).where(topic_id: ids).count
    end

    when_clauses = counts_by_ids.map { |id, count| "WHEN `id` = #{id.to_i} THEN #{count.to_i}" }

    throttle_writes_with_retry(err_msg: "From Topic.update_applied_counts") do
      self.connection.update(Arel.sql(<<~SQL, ids: ids))
        UPDATE `topics` SET `applied_count` = CASE
        WHEN NULL THEN 0
        #{when_clauses.join("\n")}
        ELSE 0
        END
        WHERE `id` IN (:ids)
      SQL
    end
  end

  # Public: Returns a relation for a weighted list of Topics matching a given query String.
  #
  # query - The search String to prefix-match on.
  # limit - An optional numeric restriction on returned results. (Default: 10)
  #
  # Results are ordered by most-frequently applied. Flagged Topics are omitted.
  #
  # Returns a Relation.
  def self.suggestions_for_autocomplete(query:, limit: 10)
    not_flagged.
      applied.
      with_name_like(query.to_s).
      order(Arel.sql("applied_count DESC")).
      limit(limit)
  end

  # Public: Returns a list of the most applied topic names. Restricts topics to
  # those used by the repositories in the given scope.
  #
  # repos - An ActiveRecord scope for Repository, or a list of repository IDs
  # limit - Defaults to 1,000 topics
  #
  # Returns a list with a length of at most the given limit.
  def self.popular_names_for_repositories(repositories:, limit: 1_000)
    popular_topic_ids_scope = RepositoryTopic.applied.
      group(:topic_id).
      where(repository_id: repositories).
      order(Arel.sql("topic_count DESC")).
      having(Arel.sql("topic_count > 1")).
      limit(limit)

    counts_by_id = Hash[popular_topic_ids_scope.pluck(
      :topic_id,
      Arel.sql("COUNT(topic_id) AS topic_count"),
    )]

    topic_ids = counts_by_id.keys
    names_by_id = Hash[where(id: topic_ids).pluck(:id, :name)]

    topic_ids.sort_by do |id|
      [-counts_by_id[id], names_by_id[id]]
    end.map { |id| names_by_id[id] }
  end

  # Public: Returns a list of the most applied topic names and how many times they are applied.
  # Restricts topics to those used by the repositories in the given scope.
  #
  # repos - An ActiveRecord scope for Repository, or a list of repository IDs
  # topic_names_cache - A hash of topic ids to topic names to avoid duplicate SQL lookups
  #
  # Returns a list tuples (topic id, topic name, count).
  def self.popular_topics_with_counts_for_repositories(repositories:, topic_names_cache: nil)
    popular_topic_ids_scope = RepositoryTopic.applied.
      group(:topic_id).
      where(repository_id: repositories).
      order(Arel.sql("topic_count DESC"))

    counts_by_id = Hash[popular_topic_ids_scope.pluck(
      :topic_id,
      Arel.sql("COUNT(topic_id) AS topic_count"),
    )]

    topic_ids = counts_by_id.keys

    missing_names = topic_ids - topic_names_cache.keys
    if missing_names.any?
      names_by_id = Hash[where(id: missing_names).pluck(:id, :name)]
    else
      names_by_id = Hash.new
    end

    topic_ids.map { |id| [id, topic_names_cache[id] || names_by_id[id], counts_by_id[id]] }
  end

  # Public: Returns the given topic name, normalized to be consistent with
  # others in the database.
  def self.normalize(name)
    return unless name
    name.squish.downcase.gsub(" ", "-").gsub("_", "-")
  end

  # Public: Returns true if the given name is a valid Topic name.
  def self.valid_name?(name)
    name.present? && name.length <= MAX_NAME_LENGTH && name =~ NAME_REGEX
  end

  # Public: Returns the given `names` array, minus any flagged topic names
  def self.filter_flagged_names(names)
    names - Topic.flagged.where(name: names).pluck(:name)
  end

  # Public: Returns a list of Topic instances for the given list of normalized names.
  #
  # Topics may be persisted or not.
  #
  # Returns an Array.
  def self.find_or_build_from_names(normalized_names, scope: Topic)
    existing_topics = scope.where(name: normalized_names)
    unpersisted_topic_names = normalized_names - existing_topics.pluck(:name)
    unpersisted_topics = unpersisted_topic_names.map { |name| new(name: name) }
    (existing_topics + unpersisted_topics).sort_by(&:name)
  end

  # Public: Return an existing Topic instance with the given normalized name.
  # Create an unpersisted Topic with a new, valid name. Return nil if no such
  # topic exists and the name is invalid.
  def self.find_or_build_by_name(name)
    normalized = normalize(name)
    built = find_by(name: normalized) || new(name: normalized)
    built.valid? ? built : nil
  end

  def self.featured_and_shuffled(limit: NUMBER_OF_FEATURED_TOPICS)
    featured
      .order("RAND()")
      .limit(limit)
  end

  def self.featured_and_sorted_alphabetically
    featured.order("name ASC")
  end

  def self.multiple_target_for_conditional_access(topics)
    ConditionalAccess::Filter.ensure_with_class(topics, Topic)

    # Topics are a public resource, not specific to any organization:
    result = {}
    topics.each do |topic|
      result[topic] = :no_target_for_conditional_access
    end
    result
  end

  def or_alias_source
    alias_source_topic || self
  end

  def human_name
    "topic"
  end

  # Public: Synchronize this topic with its representation in the search index. If the topic is
  # newly created or modified in some fashion, then it will be updated in the search index. If the
  # topic has been destroyed, then it will be removed from the search index. This method handles
  # both cases.
  def synchronize_search_index
    if self.destroyed? || flagged? || is_an_alias? || unapplied?
      RemoveFromSearchIndexJob.perform_later("topic", self.id)
    else
      Search.add_to_search_index("topic", self.id)
    end

    self
  end

  # Public: Returns an Array of topic names that are aliases of this topic.
  def alias_names
    topic_aliases.pluck(:name)
  end

  # Public: Given a list of topic names, this returns a subset of the valid names from it,
  # normalized as they would be when saved to the `topics` table.
  #
  # Returns an Array of unique Strings.
  def self.normalize_and_extract_valid_names(topic_names)
    topic_names.compact.map { |name| normalize(name) }.select { |name| valid_name?(name) }.uniq
  end

  # Public: Replace this Topic's aliases using the given list of names.
  #
  # Returns nothing.
  def update_aliases_from_names(topic_names)
    update_relations_from_names(topic_names, delimiter: ALIAS_DELIMITER, relation_type: :alias)
  end

  # Public: Returns the topic relation that ties this topic to a "source" topic as an alias.
  #
  # Returns a TopicRelation or nil.
  def alias_source_topic_relation
    TopicRelation.alias.where(name: name).order("topic_relations.id DESC").includes(:topic).first
  end

  # Public: Returns the topic for which this topic is an alias.
  #
  # Returns a Topic or nil.
  def alias_source_topic
    alias_source_topic_relation.try(:topic)
  end

  # Public: Indicates whether this topic is itself an alias of some other topic, e.g., reactjs is
  # an alias of react.
  #
  # Returns a Boolean.
  def is_an_alias?
    !alias_source_topic.nil?
  end

  # Public: Returns an Array of topic names that are related to this topic.
  def related_topic_names
    related_topics.pluck(:name)
  end

  # Public: Replace this Topic's related topics using the given list of names.
  #
  # Returns nothing.
  def update_related_topics_from_names(topic_names)
    update_relations_from_names(topic_names, delimiter: RELATED_DELIMITER, relation_type: :related)
  end

  # Public: Returns names of topics related to the given name, using our own curated
  # list. By default this does not include aliases.
  #
  # Returns an array of Strings.
  def self.related_to(name)
    names = []
    topic = Topic.find_by(name: name)

    if topic
      names.concat(topic.related_topic_names)
    end

    names -= [name]
    filter_flagged_names(names.uniq)
  end

  # Public: Returns topics related to the given name.
  # Only returns topics that are applied to repositories. Topics are sorted
  # with the most relevant first.
  #
  # Returns an array of Topics, or nil if there was an error.
  def self.applied_and_related_to(name, limit: 10)
    names = related_to(name)
    return [] unless names

    names = names.first(limit)
    applied_and_named = not_flagged.applied.where(name: names)

    applied_and_named.sort_by do |topic|
      names.index(topic.name)
    end
  end

  # Public: This returns a substring of the given String if it's a featured Topic.
  #
  # Returns a String or nil.
  def self.extract_featured_topic_name(input)
    all_featured_names = featured_names

    normalized_input = normalize(input)
    return normalized_input if all_featured_names.include?(normalized_input)

    # Look at individual words, see if one is a featured topic:
    words = input.downcase.split(/\s+/)
    topic_name = words.detect { |word| all_featured_names.include?(word) }
    return topic_name if topic_name

    # Treat the entire input string as one giant topic, see if some substring is actually a
    # featured topic:
    all_featured_names.each do |topic_name|
      if match = normalized_input.match(/\b(#{topic_name})\b/)
        return match[0]
      end
    end

    nil
  end

  # Public: Returns the Topic instance with the given name, normalized, or nil
  # if no such Topic exists.
  def self.find_by_name(name)  # rubocop:disable GitHub/FindByDef
    where(name: normalize(name)).first
  end

  # Public: Determine if this Topic is applied to any repositories, as opposed to being a rejected
  # suggestion.
  #
  # Returns a Boolean.
  def unapplied?
    !applied_repository_topics.exists?
  end

  # Public: Return the number of days since the latest release.
  #
  # Returns a String or nil.
  def formatted_days_since(release)
    return unless release

    if release.created_at > 1.day.ago
      "Today"
    else
      "#{time_ago_in_words(release.created_at)} ago"
    end
  end

  # Public: Returns true if the github_url method will return a URL for a repository, as opposed
  # to a user or organization.
  def github_url_is_repository?
    nwo = repository_name_with_owner
    return false unless nwo

    path_parts = nwo.split("/").reject(&:blank?)

    # A repo will have two parts, owner/name, as opposed to a user or org having only the name:
    path_parts.size == 2
  end

  # Public: Returns the latest release for the this topic's related repository, if it exists.
  #
  # Returns a Release or nil.
  def latest_release(user)
    Releases::Public.latest_for_repository(repository, user) if repository
  end

  # Public: Returns the public repository associated with this topic, if one exists.
  def repository
    return unless github_url

    uri = URI(T.must(github_url))
    owner_name, repo_name = T.must(uri.path)[1..-1]&.split("/")

    Repository.with_name_with_owner(owner_name, repo_name) if repo_name
  end

  # Public: Returns an array of the names of featured Topics.
  def self.featured_names
    alias_type = TopicRelation.relation_types[:alias]
    names_query = featured.
      joins("LEFT OUTER JOIN topic_relations " \
            "ON topic_relations.topic_id = topics.id " \
            "AND topic_relations.relation_type = #{alias_type}").
      select("topics.name AS topic_name, topic_relations.name AS topic_relation_name")
    names_query = T.cast(names_query, ActiveRecord::Relation)
    names = names_query.map(&:topic_name) + names_query.map(&:topic_relation_name)
    names.compact.uniq.sort
  end

  # Public: Returns true if we have curated content for this Topic.
  def curated?
    short_description.present?
  end

  # Public: Always returns true. Topics can't be private.
  # This method is required by the starring api.
  def public?
    true
  end

  def global_id
    name
  end

  # Public: Return the display name if one has been set. Fall back to the
  # name if it has not.
  def safe_display_name
    display_name.presence || name
  end

  def resource_path
    template = if GitHub.enterprise?
      "/search?q=topic%3A{name}&type=Repositories"
    else
      "/topics/{name}"
    end

    Addressable::Template.new(template).expand(name: name)
  end

  def resource_url
    origin = Addressable::URI.parse(GitHub.url)

    resource_path.dup.tap do |full_uri|
      full_uri.scheme = origin.scheme
      full_uri.host = origin.host
      full_uri.port = origin.port
    end
  end

  def public_repo_count_max
    PUBLIC_REPO_COUNT_MAX
  end

  private

  def repository_name_with_owner
    return unless github_url.present?
    path = URI(T.must(github_url)).path
    T.must(path).gsub(/\A\//, "").gsub(/\/\z/, "") # remove leading + trailing slashes
  end

  def update_relations_from_names(topic_names, delimiter:, relation_type:)
    normalized_names = self.class.normalize_and_extract_valid_names(topic_names.split(delimiter))

    # Make sure relations we're keeping have the right relation_type:
    update_relation_type(normalized_names, relation_type)

    # Delete relations we no longer want:
    delete_other_relations(normalized_names, relation_type)

    # Add new relations:
    add_relations_from(normalized_names, relation_type)
  end

  def update_relation_type(normalized_names, relation_type)
    topic_relations.
      without_relation_type(relation_type).
      where(name: normalized_names).
      update_all(relation_type: TopicRelation.relation_types[relation_type])
  end

  def delete_other_relations(normalized_names, relation_type)
    names_to_remove = topic_relations.pluck(:name) - normalized_names
    topic_relations.
      with_relation_type(relation_type).
      where(name: names_to_remove).
      destroy_all
  end

  def add_relations_from(normalized_names, relation_type)
    existing_names = topic_relations.with_relation_type(relation_type).pluck(:name)
    names_to_add = normalized_names - existing_names
    names_to_add.map do |name|
      topic_relations.create(name: name, relation_type: relation_type)
    end
  end

  # Private: Normalizes the name on this Topic.
  def normalize_name
    return unless T.unsafe(name)
    self.name = self.class.normalize(name)
  end

  def instrument_flag_unflag
    return unless previous_changes["flagged"].present?

    if previous_changes["flagged"].first == false && flagged?
      instrument :flag, flag_event_payload
    elsif previous_changes["flagged"].first == true && !flagged?
      instrument :unflag, flag_event_payload
    end
  end

  def flag_event_payload
    user = User.find_by(id: GitHub.context[:actor_id]) || User.ghost
    actor_context = GitHub.guarded_audit_log_staff_actor_entry(user)

    {
      name: name,
      flagged: flagged?,
      applied_count: applied_count,
    }.merge(actor_context)
  end
end
