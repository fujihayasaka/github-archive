# typed: true
# frozen_string_literal: true

class RepositoryTopic < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include GitHub::BatchedScope

  belongs_to :topic
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repository)
  belongs_to :user

  LIMIT_PER_REPOSITORY = 20
  DEFAULT_APPLIED_TO_LIMIT = 1_000

  enum :state, {
    # A topic that was manually added by a user to a repository.
    created: 1,

    # A topic that was suggested via the Munger service
    # and accepted and applied by a user to a repository.
    suggested: 2,

    # A topic that was suggested via the Munger service
    # and declined by the user as not being relevant to the repository.
    declined_not_relevant: 3,

    # A topic that was suggested via the Munger service
    # and declined by the user due to it being too specific
    # (e.g. #ruby-on-rails-version-4-2-1).
    declined_too_specific: 4,

    # A topic that was suggested via the Munger service
    # and declined by the user due to personal preference.
    declined_personal_preference: 5,

    # A topic that was suggested via the Munger service
    # and declined by the user due to it being too general.
    declined_too_general: 6,
  }

  APPLIED_STATES = %w(created suggested).freeze
  APPLIED_STATE_VALUES = APPLIED_STATES.map { |state| self.states[state] }.freeze

  # Public: Whether a validation should ensure the repository is not at its limit for topics.
  attr_accessor :skip_topic_limit_check

  # Public: Whether a validation should ensure the topic is not already applied to the repository.
  attr_accessor :skip_uniqueness_check

  validates :topic, :repository, :state, :user_id, presence: true
  validates :state, presence: true
  validates :repository_id, uniqueness: { scope: [:topic_id] }, unless: :skip_uniqueness_check
  validate :repo_topic_limit_not_reached, on: :create, unless: :skip_topic_limit_check

  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_add_topic, on: :create, if: :applied? # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_remove_topic, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Includes only records for topics users manually applied or accepted from
  # suggestions.
  scope :applied, -> { where(state: applied_state_values) }

  # Includes only RepositoryTopics for public repositories.
  scope :on_public_repositories, -> { joins(:repository).merge(Repository.public_scope) }

  # Includes only records for topic suggestions that the user rejected.
  scope :declined_suggestions, -> { where("state NOT IN (?)", applied_state_values) }

  # Orders the repo topics by how recently they were added to a repository.
  scope :newest_first, -> { order("repository_topics.id DESC") }

  # Returns a scope for RepositoryTopics applied to a set of Repository records.
  def self.applied_to(repository_ids: [], limit: DEFAULT_APPLIED_TO_LIMIT)
    return none if repository_ids.empty?

    applied.distinct.limit(limit).where(repository_id: repository_ids)
  end

  # Public: Returns an array of integers for the RepositoryTopic states that indicate the
  # Topic has been applied to the Repository and not rejected for it.
  def self.applied_state_values
    APPLIED_STATE_VALUES
  end

  def self.names_for(repository_ids:, limit_per_repo:)
    repo_ids_and_topic_ids = RepositoryTopic.
      applied_to(repository_ids: repository_ids).
      pluck(:repository_id, :topic_id).
      each_with_object({}) do |(repo_id, topic_id), acc|
        acc[repo_id] ||= []
        acc[repo_id] << topic_id
      end
    topic_ids_and_topic_names = Topic.
      where(id: repo_ids_and_topic_ids.values.flatten).
      pluck(:id, :name).
      to_h

    topic_names_by_repo_id = repo_ids_and_topic_ids.map do |repo_id, topic_ids|
      [repo_id, topic_ids.first(limit_per_repo).map { |id| topic_ids_and_topic_names[id] }]
    end

    topic_names_by_repo_id.to_h
  end

  # Public: Update existing repo-topic records to change their user and state.
  #
  # repository - the Repository whose repo-topics you want to change
  # topic_ids - Array of Integer Topic IDs to update the repo-topic records for
  # user - the User to set for each repo-topic
  #
  # Returns a list of RepositoryTopic records with necessary changes persisted, or raises ActiveRecord::RecordInvalid
  # on error.
  def self.update_states_and_users(repository:, topic_ids:, user:)
    existing_repo_topics = repository.repository_topics.where(topic_id: topic_ids).includes(:topic)

    existing_repo_topics.each do |repo_topic|
      repo_topic.state = :created
      repo_topic.user = user

      if repo_topic.changed?
        # Avoid extra read to check for existing repo-topic since we're not changing the repo or topic:
        repo_topic.skip_uniqueness_check = true

        repo_topic.save!
      end
    end

    existing_repo_topics
  end

  # Public: Insert multiple new repo-topic records for the specified repository and topics, omitting any that are
  # already applied to the repository.
  #
  # repository - the Repository to apply topics to
  # topics - an Array of Topics to apply to the repository
  # user - the User who is applying the topics
  # existing_repo_topics - Array of RepositoryTopic records that already exist for the Repository
  # suggested_topic_names - Set of String Topic names that were suggested for the specified repository,
  #                         to use in determining whether the `state` for a repo-topic should be "suggested"
  #                         versus "created"
  #
  # Returns an Array of persisted RepositoryTopic records, or raises ActiveRecord::RecordInvalid on error.
  def self.create_missing(repository:, topics:, user:, existing_repo_topics:)
    already_applied_topic_ids = existing_repo_topics.map(&:topic_id).to_set
    new_topics_to_apply = topics.reject { |topic| already_applied_topic_ids.include?(topic.id) }
    new_repo_topics = []
    skip_topic_limit_check = new_topics_to_apply.size + existing_repo_topics.size <= LIMIT_PER_REPOSITORY

    new_topics_to_apply.map do |topic|
      repo_topic = RepositoryTopic.new(topic: topic, repository: repository, state: :created, user: user)
      repo_topic.skip_topic_limit_check = skip_topic_limit_check

      # Because of the `existing_repo_topics` check, can skip the individual record validation for an
      # existing repo-topic:
      repo_topic.skip_uniqueness_check = true

      begin
        repo_topic.save!
      rescue ActiveRecord::RecordNotUnique
        next
      end
      new_repo_topics << repo_topic
    end

    new_repo_topics
  end

  # Public: Apply the given topic names to this repository. If any topics on the repository
  # are omitted from this list, they will be removed.
  #
  # raw_topic_names - Array of String topic names that haven't been normalized and aren't known to be valid yet
  # user - the User who is changing this repository's topics
  #
  # Returns true if all topics on the repository were updated to match the given list, or false
  # on error.
  def self.replace(repository, raw_topic_names, user:)
    old_topic_names = repository.topics.pluck(:name)

    # if empty delete all topics
    unless raw_topic_names.present?
      repository.applied_repository_topics.destroy_all
      repository.touch
      if !old_topic_names.empty?
        instrument_topic_updates(repository, old_topic_names, user)
      end
      return true
    end

    remove_omitted(repository, raw_topic_names)

    valid_topic_names = Topic.normalize_and_extract_valid_names(raw_topic_names)
    return false if valid_topic_names.size > RepositoryTopic::LIMIT_PER_REPOSITORY

    topics = Topic.ensure_names_exist(valid_topic_names)

    begin
      existing_repo_topics = RepositoryTopic.update_states_and_users(repository:, topic_ids: topics.map(&:id),
        user: user)
      RepositoryTopic.create_missing(repository:, topics:, user:, existing_repo_topics:)
    rescue ActiveRecord::RecordInvalid
      return false
    end

    repository.touch

    new_topic_names = topics.map(&:name)
    if old_topic_names.to_set != new_topic_names.to_set
      instrument_topic_updates(repository, old_topic_names, user)
    end

    true
  end

  # Public: Remove all topics from this repository whose name is not in the given list.
  # Returns nothing.
  def self.remove_omitted(repository, names_to_keep)
    normalized_names = names_to_keep.map { |name| Topic.normalize(name) }

    topics_to_remove = repository.topics
    if normalized_names.present?
      topics_to_remove = topics_to_remove.where(ActiveRecord::Base.sanitize_sql(["name NOT IN (?)", normalized_names]))
    end
    topics_to_remove = topics_to_remove.pluck(:id)

    ActiveRecord::Base.connected_to(role: :writing) do
      repository.applied_repository_topics.where(topic_id: topics_to_remove).destroy_all
    end
  end

  def self.autocompleted_names(repository:, query:, viewer:)
    return [] unless repository.can_manage_topics?(viewer) # rubocop:todo GitHub/AvoidCast

    suggestions = []
    queried_suggestions = []

    if query.present?
      suggestions.select! { |name| name.start_with?(query) }
      queried_suggestions = ::Topic.suggestions_for_autocomplete(query: query, limit: 10).pluck(:name)
    end

    suggestions.concat(queried_suggestions)

    associated_topic_ids = ::Topic.where(id: ::RepositoryTopic.applied_to(
      repository_ids: [repository.id],
    ).pluck(:topic_id))
    associated_topics = ::Topic.where(id: associated_topic_ids).pluck(:name)

    suggestions.uniq - associated_topics
  end

  # Reindex the Repository and Topic in ElasticSearch.
  def synchronize_search_index
    if repository
      T.must(repository).synchronize_search_index
      T.must(repository).packages.each(&:synchronize_search_index)
    end

    T.must(topic).synchronize_search_index if topic
  end

  # Public: Whether or not the topic was applied to the repository.
  # Returns a Boolean.
  def applied?
    APPLIED_STATES.include?(state)
  end

  # Attributes to serialize for the Migrations API.
  def migration_attributes
    {
      topic_url:     topic.try(:url),
      topic_name:    topic.try(:name),
      repository:    repository,
      creator:       user,
      state:         state,
      created_at:    created_at,
      updated_at:    updated_at
    }
  end

  def topic_name
    topic&.name
  end

  private

  def self.instrument_topic_updates(repository, old_topic_names, actor)
    changes = {
      old_topics: old_topic_names,
      topics: repository.topics.pluck(:name)
    }
    repository.instrument :update, actor: actor || repository.owner, changes: changes
  end
  private_class_method :instrument_topic_updates

  # Audit log event payload.
  def event_payload
    {
      topic:         topic.try(:name),
      topic_id:      topic.try(:id),
      state:         state,
      repo:          repository,
      user:          user,
      user_id:       user.try(:id),
      org:           repository.try(:organization),
      org_id:        repository.try(:organization).try(:id),
      repository_topic_id: id,
    }
  end

  def instrument_add_topic
    instrument :add_topic
    GlobalInstrumenter.instrument("topic", {
      repository: self.repository,
      repository_owner: self.repository&.owner,
      topic: self.topic,
      action: :ACTION_TOPIC_CREATED,
      actor: user,
      timestamp: Time.now
    })
  end

  def instrument_remove_topic
    instrument :remove_topic
    GlobalInstrumenter.instrument("topic", {
      repository: self.repository,
      repository_owner: self.repository&.owner,
      topic: self.topic,
      action: :ACTION_TOPIC_DELETED,
      actor: user,
      timestamp: Time.now
    })
  end

  # Audit log event prefix.
  def event_prefix
    :repo
  end

  def repo_topic_limit_not_reached
    return unless repository

    existing_topic_count = T.must(repository).applied_repository_topics.count

    unless existing_topic_count < LIMIT_PER_REPOSITORY
      errors.add(:repository, "cannot have more than #{LIMIT_PER_REPOSITORY} topics.")
    end
  end
end
