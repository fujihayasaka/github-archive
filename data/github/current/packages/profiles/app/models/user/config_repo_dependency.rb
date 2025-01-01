# typed: strict
# frozen_string_literal: true

module User::ConfigRepoDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  # Public: Topics to be applied to new configuration repositories upon creation. This list should not exceed
  # RepositoryTopic::LIMIT_PER_REPOSITORY topics.
  CONFIG_REPO_TOPIC_NAMES = %w(config github-config).freeze
  ALTERNATE_CONFIG_REPO_NAME = ".github"

  included do
    T.bind(self, T.class_of(User))

    has_one :configuration_repository, ->(user) do
      T.bind(self, T.untyped)

      if user.user?
        if user.feature_enabled?(:alternate_user_config_repo)
          active
            .where(name: [user.config_repo_name, ALTERNATE_CONFIG_REPO_NAME])
            .order(Arel.sql("CASE name WHEN '#{user.config_repo_name}' THEN 0 ELSE 1 END"))
        else
          active.where(name: user.config_repo_name)
        end
      else
        none
      end
    end, foreign_key: :owner_id, inverse_of: :owner, class_name: :Repository
  end

  sig { returns(String) }
  def config_repo_name
    login
  end

  sig { returns(T::Boolean) }
  def has_configuration_repository?
    configuration_repository.present?
  end

  sig { returns(T::Boolean) }
  def using_alternate_configuration_repository?
    return false unless feature_enabled?(:alternate_user_config_repo)

    config_repo = configuration_repository
    return false unless config_repo.present?
    config_repo.name == ALTERNATE_CONFIG_REPO_NAME
  end

  sig { returns(Promise[T::Boolean]) }
  def async_using_alternate_configuration_repository?
    return Promise.resolve(T.let(false, T::Boolean)) unless feature_enabled?(:alternate_user_config_repo)

    async_configuration_repository.then do |config_repo|
      next false unless config_repo.present?
      config_repo.name == ALTERNATE_CONFIG_REPO_NAME
    end
  end

  sig do
    params(
      is_public: T::Boolean,
      reflog_data: T::Hash[T.untyped, T.untyped],
      auto_init: T::Boolean,
    ).returns(T.nilable(Repository))
  end
  def create_configuration_repository(is_public:, reflog_data: {}, auto_init: true)
    T.bind(self, User)
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
