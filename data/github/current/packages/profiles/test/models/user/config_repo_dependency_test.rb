# typed: true
# frozen_string_literal: true

require "test_helper"

class UserConfigurationRepositoryDependencyTest < GitHub::TestCase
  setup do
    @user = create(:user)
  end

  context "CONFIG_REPO_TOPIC_NAMES validations" do
    test "within limit for how many topics can be applied to a repository" do
      assert_operator User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.size, :<=, RepositoryTopic::LIMIT_PER_REPOSITORY
    end

    test "contains valid topic names" do
      User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.each do |topic_name|
        assert Topic.valid_name?(topic_name), "'#{topic_name}' is not a valid name for a topic"
      end
    end
  end

  context "#create_configuration_repository" do
    test "creates a new config repo for the user" do
      reflog_data = {}
      refute_predicate @user, :has_configuration_repository?
      assert_nil @user.configuration_repository

      config_repo = assert_difference({
        "RepositoryTopic.count" => User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.size,
        "Topic.count" => User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.size,
        "Repository.count" => 1,
      }) do
        @user.create_configuration_repository(is_public: true, reflog_data: reflog_data)
      end

      refute_nil @user.reload_configuration_repository
      assert_predicate @user, :has_configuration_repository?
      assert_instance_of Repository, config_repo
      assert_predicate config_repo, :public?
      assert_predicate config_repo, :has_readme?
      assert_equal User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES, config_repo.topic_names
    end

    test "uses existing topics" do
      reflog_data = {}
      refute_predicate @user, :has_configuration_repository?
      assert_nil @user.configuration_repository
      existing_topic = create(:topic, name: User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.first)

      config_repo = assert_difference({
        "RepositoryTopic.count" => User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.size,
        "Topic.count" => User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES.size - 1,
        "Repository.count" => 1,
      }) do
        @user.create_configuration_repository(is_public: true, reflog_data: reflog_data)
      end

      refute_nil @user.reload_configuration_repository
      assert_predicate @user, :has_configuration_repository?
      assert_instance_of Repository, config_repo
      assert_predicate config_repo, :public?
      assert_predicate config_repo, :has_readme?
      assert_equal User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES, config_repo.topic_names
    end

    test "doesn't auto init if auto_init is false" do
      reflog_data = {}
      refute_predicate @user, :has_configuration_repository?
      assert_nil @user.configuration_repository

      config_repo = assert_difference("RepositoryTopic.count", 2) do
        @user.create_configuration_repository(
          is_public: true,
          reflog_data: reflog_data,
          auto_init: false,
        )
      end

      refute_nil @user.reload_configuration_repository
      assert_predicate @user, :has_configuration_repository?
      assert_instance_of Repository, config_repo
      assert_predicate config_repo, :public?
      refute_predicate config_repo, :has_readme?
      assert_equal User::ConfigRepoDependency::CONFIG_REPO_TOPIC_NAMES, config_repo.topic_names
    end
  end

  context "#has_configuration_repository?" do
    test "false when user has no config repo" do
      refute_predicate @user, :has_configuration_repository?
    end

    test "true when user has a config repo" do
      create(:repository, owner: @user, name: @user.config_repo_name)
      assert_predicate @user, :has_configuration_repository?
    end
  end

  context "configuration_repository relation" do
    test "returns user's public config repo if it exists" do
      config_repo = create(:repository, owner: @user, name: @user.config_repo_name)
      assert_equal config_repo, @user.configuration_repository
    end

    test "returns nil when user does not have a public config repo" do
      assert_nil @user.configuration_repository
    end

    test "returns user's private config repo if it exists" do
      config_repo = create(:private_repository, owner: @user, name: @user.config_repo_name)
      assert_equal config_repo, @user.configuration_repository
    end
  end
end
