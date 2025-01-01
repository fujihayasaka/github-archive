# typed: strict
# frozen_string_literal: true

class TopicRelation < ApplicationRecord::Domain::Topics
  extend T::Sig

  belongs_to :topic

  before_validation :normalize_name
  after_commit :synchronize_search_index # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  MAX_TOPIC_ALIASES = 120
  MAX_RELATED_TOPICS = 10

  validates :name, :topic, presence: true
  validates :relation_type, presence: true
  validates :name, length: { maximum: Topic::MAX_NAME_LENGTH },
    format: {
      with: Topic::NAME_REGEX,
      message: "can only include letters, numbers, and hyphens, e.g., node-js-6-3-1",
    }
  validates :name, uniqueness: {
    scope: :topic_id,
    case_sensitive: false
  }, if: ->(topic) { topic.errors[:name].blank? }
  validate :name_is_not_already_an_alias_for_another_topic
  validate :under_topic_alias_limit
  validate :under_related_topic_limit

  enum :relation_type, { alias: 0, related: 1 }

  scope :with_relation_type, ->(relation_type) {
    where(relation_type: TopicRelation.relation_types[relation_type] || relation_type)
  }

  scope :without_relation_type, ->(relation_type) {
    where("topic_relations.relation_type <> ?", TopicRelation.relation_types[relation_type] || relation_type)
  }

  # Public: Indicates if this relation is for a featured topic.
  sig { returns(T::Boolean) }
  def is_topic_featured?
    return false unless this_topic = topic
    this_topic.featured?
  end

  # Public: Reindex the topic that's marked as an alias in ElasticSearch.
  sig { void }
  def synchronize_search_index
    return unless alias?
    other_topic = Topic.where(name: name).first
    other_topic.synchronize_search_index if other_topic
  end

  private

  sig { void }
  def under_topic_alias_limit
    return unless this_topic = topic

    existing_alias_count = this_topic.topic_aliases.count
    unless existing_alias_count < MAX_TOPIC_ALIASES
      errors.add(:topic, "cannot have more than #{MAX_TOPIC_ALIASES} aliases")
    end
  end

  sig { void }
  def under_related_topic_limit
    return unless this_topic = topic

    existing_related_count = this_topic.related_topics.count
    unless existing_related_count < MAX_RELATED_TOPICS
      errors.add(:topic, "cannot have more than #{MAX_RELATED_TOPICS} related topics")
    end
  end

  # Private: Normalizes the name on this RelatedTopic.
  sig { void }
  def normalize_name
    self.name = Topic.normalize(name)
  end

  sig { void }
  def name_is_not_already_an_alias_for_another_topic
    return unless errors[:name].blank?
    return unless alias?

    existing_relations = self.class.alias.where(name: name).where("topic_id <> ?", topic_id)

    if existing_relations.exists?
      errors.add(:name, "is already an alias for another topic")
    end
  end
end
