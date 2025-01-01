# typed: false
# frozen_string_literal: true

module User::ConfigRepoDependency
  extend ActiveSupport::Concern

  # Public: Topics to be applied to new configuration repositories upon creation. This list should not exceed
  # RepositoryTopic::LIMIT_PER_REPOSITORY topics.
  CONFIG_REPO_TOPIC_NAMES = %w(config github-config).freeze

  included do
    has_one :configuration_repository, ->(user) do
      if user.user?
        active.where(name: user.config_repo_name)
      else
        none
      end
    end, foreign_key: :owner_id, inverse_of: :owner, class_name: :Repository
  end

  def config_repo_name
    login
  end

  def has_configuration_repository?
    configuration_repository.present?
  end

  def create_configuration_repository(is_public:, reflog_data: {}, auto_init: true)
    return unless user?

    repo_attrs = {
      name: config_repo_name,
      description: "Config files for my GitHub profile.",
      auto_init: auto_init,
      has_wiki: false,
      has_issues: false,
      homepage: "#{GitHub.url}/#{login}", # URL to the user profile
      public: is_public,
    }
    reflog_data = reflog_data.merge(
      repo_name: "#{login}/#{config_repo_name}",
      repo_public: is_public,
    )
    result = Repository.handle_creation(self, login, repo_attrs, reflog_data)
    config_repo = result.repository

    if result.success?
      topics = Topic.ensure_names_exist(CONFIG_REPO_TOPIC_NAMES)
      topics.take(RepositoryTopic::LIMIT_PER_REPOSITORY).each do |topic|
        repo_topic = RepositoryTopic.new(topic: topic, repository: config_repo, state: :created, user: self)

        # Avoid reads to look up existing repo-topics since these are being applied to a new repository that
        # has no topics yet:
        repo_topic.skip_topic_limit_check = true
        repo_topic.skip_uniqueness_check = true

        repo_topic.save
      end
    end

    config_repo
  end
end
