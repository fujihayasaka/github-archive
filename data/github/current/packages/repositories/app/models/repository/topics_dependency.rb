# typed: true
# frozen_string_literal: true

module Repository::TopicsDependency
  extend T::Helpers

  requires_ancestor { Repository }

  extend ActiveSupport::Concern

  included do
    T.bind(self, T.class_of(Repository))

    has_many :repository_topics, dependent: :destroy

    has_many :applied_repository_topics,
      -> { where(state: RepositoryTopic.applied_state_values) },
      class_name: "RepositoryTopic"

    has_many :topics, through: :applied_repository_topics, disable_joins: true

    batch_method(:topic_names) do |repos|
      topic_names_by_repo_id = RepositoryTopic.names_for(
        repository_ids: repos.map(&:id),
        limit_per_repo: 1000,
      )

      repos.index_with do |repo|
        topic_names_by_repo_id[repo.id]&.compact&.sort || []
      end
    end
  end

  def invalid_topic_names
    @invalid_topic_names ||= []
  end

  def update_topics(topic_names, user:)
    invalid_names = topic_names.reject { |name| Topic.valid_name?(name) }
    if invalid_names.any?
      error_message = "must start with a lowercase letter or number, " \
                      "consist of #{Topic::MAX_NAME_LENGTH} characters or less, and can include hyphens."
      errors.add(:repository_topics, error_message)
      invalid_topic_names.concat(invalid_names)
      return false
    end

    limit = ::RepositoryTopic::LIMIT_PER_REPOSITORY
    if topic_names.size > limit
      error_message = "A repository cannot have more than #{limit} topics."
      errors.add(:repository_topics, error_message)
      invalid_topic_names.concat(topic_names[limit..-1])
      return false
    end

    RepositoryTopic.replace(self, topic_names, user: user)
  end

  private

  def synchronize_topics_search_index
    GitHub.dogstats.distribution_time("repository.synchronize_topics_search_index") do
      topics.each(&:synchronize_search_index)
    end
  end
end
