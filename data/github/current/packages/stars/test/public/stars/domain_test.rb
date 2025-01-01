# typed: true
# frozen_string_literal: true

require "test_helper"

class StarsDomainTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @gist = create(:gist)
    @topic = create(:topic)
  end

  setup do
    @domain = T.let(Stars::Domain.new(:test), T.nilable(Stars::Domain))
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Stars::Domain) }
  def domain
    T.must(@domain)
  end

  context "user_starred_topics_count" do
    test "returns the count of starred topics for the given user_id" do
      topic = create(:topic)
      create(:star, user: @user, starrable: topic)

      assert_equal 1, domain.user_starred_topics_count(@user.id)
    end

    test "returns 0 if the user has not starred any topics" do
      user = create(:user)

      assert_equal 0, domain.user_starred_topics_count(@user.id)
    end
  end

  context "user_starred_topic_ids" do
    test "returns the ids of the topics that the user has starred" do
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: @topic)

      assert_equal [@topic.id], domain.user_starred_topic_ids(@user.id)
    end
  end

  context "user_starred_repository_ids" do
    test "returns the ids of the repositories that the user has starred" do
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: @topic)

      assert_equal [@repo.id], domain.user_starred_repository_ids(@user.id)
    end

    test "applies the repo_ids if provided" do
      second_repo = create(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: second_repo)

      repo_ids = [second_repo.id]
      assert_equal repo_ids, domain.user_starred_repository_ids(@user.id, repo_ids: repo_ids)
    end

    test "applies the limit if provided" do
      second_repo = create(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: second_repo)

      assert_equal [@repo.id], domain.user_starred_repository_ids(@user.id, limit: 1)
    end
  end

  context "user_most_recently_starred_repo_ids" do
    test "returns the ids of the repositories that the user has starred" do
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: @topic)

      assert_equal [@repo.id], domain.user_most_recently_starred_repo_ids(@user.id, 1)
    end

    test "applies the limit if provided" do
      second_repo = create(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo, created_at: 2.days.ago)
      create(:star, user: @user, starrable: second_repo, created_at: 1.day.ago)

      assert_equal [second_repo.id], domain.user_most_recently_starred_repo_ids(@user.id, 1)
    end

    test "returns the most recently starred repos" do
      second_repo = create(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo, created_at: 2.days.ago)
      create(:star, user: @user, starrable: second_repo, created_at: 1.day.ago)

      assert_equal [second_repo.id, @repo.id], domain.user_most_recently_starred_repo_ids(@user.id, 2)
    end
  end

  context "user_any_starred_repositories?" do
    test "returns true if the user has starred a repository" do
      create(:star, user: @user, starrable: @repo)

      assert domain.user_any_starred_repositories?(@user.id)
    end

    test "returns false if the user has not starred any repository" do
      create(:star, user: @user, starrable: @topic)

      refute domain.user_any_starred_repositories?(@user.id)
    end
  end

  context "user_starred_repositories_count" do
    test "returns the count of repositories that the user has starred" do
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: @topic)

      assert_equal 1, domain.user_starred_repositories_count(@user.id)
    end
  end

  context "repo_starred_user_ids" do
    test "returns the ids of the users who starred the repository" do
      user2 = create(:user)
      user3 = create(:user)
      create(:star, user: @user, starrable: @repo)
      create(:star, user: user2, starrable: @repo)
      create(:star, user: user3, starrable: @repo)

      assert_equal [user3.id, user2.id, @user.id], domain.repo_starred_user_ids(@repo.id, since: 1.month.ago)
    end

    test "returns an empty array if no users starred the repository" do
      assert_empty domain.repo_starred_user_ids(@repo.id, since: 1.month.ago)
    end

    test "returns the ids of the users who starred the repository since the given timestamp" do
      user2 = create(:user)
      user3 = create(:user)
      create(:star, user: @user, starrable: @repo, created_at: 3.days.ago)
      create(:star, user: user2, starrable: @repo, created_at: 1.day.ago)
      create(:star, user: user3, starrable: @repo, created_at: 1.month.ago)

      assert_equal [user2.id, @user.id], domain.repo_starred_user_ids(@repo.id, since: 1.week.ago)
    end
  end

  context "user_can_star?" do
    test "returns true for success" do
      assert domain.user_can_star?(user: @user, entity: @repo)
    end

    test "returns false when user is not authorized to star" do
      ContentAuthorizer.expects(:authorize).returns(stub(passed?: false))
      refute domain.user_can_star?(user: @user, entity: @repo)
    end

    test "returns false when already starred" do
      assert domain.user_can_star?(user: @user, entity: @repo)
      assert_equal domain.star_repository(user: @user, actor: @user, repository: @repo, context: "other").class, GH::Result::Ok
      refute domain.user_can_star?(user: @user, entity: @repo)
    end
  end

  context "star_repository" do
    test "returns a value object" do
      result = T.cast(domain.star_repository(user: @user, actor: @user, repository: @repo, context: "other"), GH::Result::Ok[StarEntity])
      star_entity = StarEntity.new(**Star.find(result.value.id).attributes)
      assert_equal result.value, star_entity
    end

    test "returns error when action not allowed" do
      domain.expects(:user_can_star?).returns(false)
      result = domain.star_repository(user: @user, actor: @user, repository: @repo, context: "other")
      assert_equal result.class, GH::Result::Error
    end
  end

  context "star_gist" do
    test "returns a value object" do
      result = T.cast(domain.star_gist(user: @user, actor: @user, gist: @gist, context: "other"), GH::Result::Ok[StarEntity])
      assert_equal result.value.class, StarEntity
    end

    test "returns error when action not allowed" do
      domain.expects(:user_can_star?).returns(false)
      result = domain.star_gist(user: @user, actor: @user, gist: @gist, context: "other")
      assert_equal result.class, GH::Result::Error
    end
  end

  context "star_topic" do
    test "returns a value object" do
      result = T.cast(domain.star_topic(user: @user, actor: @user, topic: @topic, context: "other"), GH::Result::Ok[StarEntity])
      star_entity = StarEntity.new(**Star.find(result.value.id).attributes)
      assert_equal result.value, star_entity
    end
  end
end
