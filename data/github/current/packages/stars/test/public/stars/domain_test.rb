# typed: true
# frozen_string_literal: true

require "test_helper"

class StarsDomainTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @gist = create(:gist)
    @topic = create(:topic)
    @topic2 = create(:topic)

    @org = create(:organization)
    @private_repo = create(:private_repository, owner: @org)
    perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
      @org.update_default_repository_permission(:none, actor: @org.admins.first)
    end
    @org.add_member(@user)
  end

  setup do
    @domain = Stars.domain
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  sig { returns(Stars::Domain) }
  def domain
    T.must(@domain)
  end

  test "starrable?" do
    assert domain.starrable?("Repository")
    assert domain.starrable?("Topic")
    assert domain.starrable?("Gist")
    refute domain.starrable?("Issue")
  end

  context "user_starred_objects_count" do
    test "returns the count of starred topics for the given user_id" do
      create(:star, user: @user, starrable: create(:topic))
      create(:star, user: @user, starrable: create(:repository))

      assert_equal 2, domain.user_starred_objects_count(@user.id)
    end

    test "returns 0 if the user has not starred any objects" do
      user = create(:user)

      assert_equal 0, domain.user_starred_objects_count(@user.id)
    end
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

  context ".topic_star_count" do
    test "counts how many users have starred the topic" do
      topic = create(:topic)
      user1, user2 = create_pair(:user)

      assert_equal 0, domain.topic_star_count(topic.id)

      user1.star(topic)
      assert_equal 1, domain.topic_star_count(topic.id)

      user2.star(topic)
      assert_equal 2, domain.topic_star_count(topic.id)
    end

    test "excludes spammy user who starred the topic", skip_unless: :spamminess_check_enabled?  do
      soon_to_be_spammer = create(:user)
      topic = create(:topic)
      soon_to_be_spammer.star(topic)

      assert_equal 1, domain.topic_star_count(topic.id)

      staff_user = create(:staff_admin_user)
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        soon_to_be_spammer.mark_as_spammy(reason: "v spammy", actor: staff_user)
      end

      assert_equal 0, domain.topic_star_count(topic.id)
    end
  end

  context ".repository_star_count" do
    test "counts how many users have starred the repository" do
      repository = create(:repository)
      user1, user2 = create_pair(:user)

      assert_equal 0, domain.repository_star_count(repository.id)

      user1.star(repository)
      assert_equal 1, domain.repository_star_count(repository.id)

      user2.star(repository)
      assert_equal 2, domain.repository_star_count(repository.id)
    end

    test "excludes spammy user who starred the repository", skip_unless: :spamminess_check_enabled? do
      soon_to_be_spammer = create(:user)
      repository = create(:repository)
      soon_to_be_spammer.star(repository)

      assert_equal 1, domain.repository_star_count(repository.id)

      staff_user = create(:staff_admin_user)
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        soon_to_be_spammer.mark_as_spammy(reason: "v spammy", actor: staff_user)
      end

      assert_equal 0, domain.repository_star_count(repository.id)
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

  context "user_repository_stars" do
    test "returns entities for repositories that the user has starred" do
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: @topic)

      star_entity = domain.user_repository_stars(@user.id).sole
      assert_equal @user.id, star_entity.user_id
      assert_equal @repo.id, star_entity.starrable_id
      assert_equal Star::STARRABLE_TYPE_REPOSITORY, star_entity.starrable_type
      assert_equal 0, star_entity.user_hidden
    end

    test "limits by repository ids if provided" do
      second_repo, third_repo = create_pair(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: second_repo)

      star_entity = domain.user_repository_stars(@user.id, repo_ids: [second_repo.id, third_repo.id]).sole
      assert_equal @user.id, star_entity.user_id
      assert_equal second_repo.id, star_entity.starrable_id
      assert_equal Star::STARRABLE_TYPE_REPOSITORY, star_entity.starrable_type
      assert_equal 0, star_entity.user_hidden
    end

    test "applies a numerical limit if provided" do
      second_repo = create(:repository, owner: @user)
      create(:star, user: @user, starrable: @repo)
      create(:star, user: @user, starrable: second_repo)

      star_entity = domain.user_repository_stars(@user.id, limit: 1).sole
      assert_equal @user.id, star_entity.user_id
      assert_equal @repo.id, star_entity.starrable_id
      assert_equal Star::STARRABLE_TYPE_REPOSITORY, star_entity.starrable_type
      assert_equal 0, star_entity.user_hidden
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

  context "gist_starred_user_ids" do
    test "returns the ids of the users who starred the gist" do
      user2 = create(:user)
      user3 = create(:user)
      create(:gist_star, user: @user, gist: @gist)
      create(:gist_star, user: user2, gist: @gist)
      create(:gist_star, user: user3, gist: @gist)

      assert_equal [@user.id, user2.id, user3.id], domain.gist_starred_user_ids(@gist.id)
    end

    test "returns an empty array if no users starred the gist" do
      assert_empty domain.gist_starred_user_ids(@gist.id)
    end
  end

  context "repo_starred_by_user?" do
    test "returns true for a repository that user has starred" do
      create(:star, user: @user, starrable: @repo)

      assert domain.repo_starred_by_user?(@repo.id, @user.id)
    end

    test "returns false for a repository that user has not starred" do
      refute domain.repo_starred_by_user?(@repo.id, @user.id)
    end
  end

  context "topic_starred_by_user?" do
    test "returns true for a topic that user has starred" do
      create(:star, user: @user, starrable: @topic)

      assert domain.topic_starred_by_user?(@topic.id, @user.id)
    end

    test "returns false for a repository that user has not starred" do
      refute domain.topic_starred_by_user?(@topic.id, @user.id)
    end
  end

  context "gist_starred_by_user?" do
    test "returns true for a gist that user has starred" do
      @gist.stubs(:synchronize_search_index).returns(true)
      create(:gist_star, user: @user, gist: @gist)

      assert domain.gist_starred_by_user?(@gist.id, @user.id)
    end

    test "returns false for a gist that user has not starred" do
      refute domain.gist_starred_by_user?(@gist.id, @user.id)
    end
  end

  context "precache_repos_starred_by_user?" do
    test "precaches stars" do
      repo = create(:repository)
      create(:star, user: @user, starrable: repo)

      assert_query_count_per_table({ stars: 1 }) do
        domain.precache_repos_starred_by_user?([@repo.id, repo.id], @user.id)
      end

      assert_no_queries do
        refute domain.repo_starred_by_user?(@repo.id, @user.id)
        assert domain.repo_starred_by_user?(repo.id, @user.id)
      end
    end
  end

  context "precache_topics_starred_by_user?" do
    test "precaches stars" do
      topic = create(:topic)
      create(:star, user: @user, starrable: topic)

      assert_query_count_per_table({ stars: 1 }) do
        domain.precache_topics_starred_by_user?([@topic.id, topic.id], @user.id)
      end

      assert_no_queries do
        refute domain.topic_starred_by_user?(@topic.id, @user.id)
        assert domain.topic_starred_by_user?(topic.id, @user.id)
      end
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
      assert_equal domain.star_repository(user: @user, repository: @repo, context: "other").class, GH::Result::Ok
      refute domain.user_can_star?(user: @user, entity: @repo)
    end

    test "returns false for user without read access org role" do
      refute domain.user_can_star?(user: @user, entity: @private_repo)
    end

    test "returns true for user with read access org role granted directly" do
      @org.grant_org_role(assignee: @user, role: OrganizationRole.all_repo_read_role)

      assert domain.user_can_star?(user: @user, entity: @private_repo)
    end

    test "returns true for user with read access org role granted to a team" do
      team = create(:team, organization: @org)
      team.add_member(@user)
      @org.grant_org_role(assignee: team, role: OrganizationRole.all_repo_read_role)

      assert domain.user_can_star?(user: @user, entity: @private_repo)
    end
  end

  context "star_repository" do
    test "returns a value object" do
      result = T.cast(domain.star_repository(user: @user, repository: @repo, context: "other"), GH::Result::Ok[StarEntity])
      star_entity = StarEntity.new(**Star.find(result.value.id).attributes)
      assert_equal result.value, star_entity
    end

    test "returns error when action not allowed" do
      domain.expects(:user_can_star_detail).returns(GH::Result::Error.new("error"))
      result = domain.star_repository(user: @user, repository: @repo, context: "other")
      assert_equal result.class, GH::Result::Error
    end
  end

  context "star_gist" do
    test "returns a value object" do
      result = T.cast(domain.star_gist(user: @user, gist: @gist, context: "other"), GH::Result::Ok[StarEntity])
      assert_equal result.value.class, StarEntity
    end

    test "returns error when action not allowed" do
      domain.expects(:user_can_star_detail).returns(GH::Result::Error.new("error"))
      result = domain.star_gist(user: @user, gist: @gist, context: "other")
      assert_equal result.class, GH::Result::Error
    end
  end

  context "star_topic" do
    test "returns a value object" do
      result = T.cast(domain.star_topic(user: @user, topic: @topic, context: "other"), GH::Result::Ok[StarEntity])
      star_entity = StarEntity.new(**Star.find(result.value.id).attributes)
      assert_equal result.value, star_entity
    end
  end

  context "star_topics" do
    test "returns value objects" do
      results = T.cast(domain.star_topics(user: @user, topics: [@topic, @topic2], context: "other"), T::Array[GH::Result::Ok[StarEntity]])
      star_entity = StarEntity.new(**Star.find(T.must(results.first).value.id).attributes)
      star_entity2 = StarEntity.new(**Star.find(T.must(results.second).value.id).attributes)
      assert_same_elements [star_entity, star_entity2], results.map(&:value)
    end
  end

  context "repository_stars_since" do
    test "returns cached value when set" do
      repo = create(:repository)
      cache_key = StarsSince.new.send(:stars_since_cache_key, repository_id: repo.id, period: :daily)
      Stars::Kv.store.set(cache_key, "125")

      assert_equal domain.repository_stars_since(repository_id: repo.id), 125
    end

    test "sets the cache when value is not set" do
      repo = create(:repository)
      create(:star, starrable: repo)
      cache_key = StarsSince.new.send(:stars_since_cache_key, repository_id: repo.id, period: :daily)

      assert_changes -> { Stars::Kv.store.exists(cache_key).value! }, from: false, to: true do
        assert_equal domain.repository_stars_since(repository_id: repo.id), 1
      end
    end
  end

  context "repositories_stars_since" do
    test "returns cached value when set" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      cache_key = StarsSince.new.send(:stars_since_cache_key, repository_id: repo1.id, period: :daily)
      Stars::Kv.store.set(cache_key, "125")

      counts = { repo1.id => 125, repo2.id => 0 }
      assert_equal counts, domain.repositories_stars_since(repository_ids: [repo1.id, repo2.id])
    end

    test "limits to 100 IDs" do
      assert_raises_with_message(ArgumentError, "Too many repository_ids") do
        domain.repositories_stars_since(repository_ids: [*1..101])
      end
    end

    test "sets the cache when value is not set" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      create(:star, starrable: repo1)
      cache_key = StarsSince.new.send(:stars_since_cache_key, repository_id: repo1.id, period: :daily)

      assert_changes -> { Stars::Kv.store.exists(cache_key).value! }, from: false, to: true do
        counts = { repo1.id => 1, repo2.id => 0 }
        assert_equal counts, domain.repositories_stars_since(repository_ids: [repo1.id, repo2.id])
      end
    end
  end

  context "repository_latest_star" do
    test "returns latest star" do
      star1 = Timecop.freeze(2.hours.ago) do
        create(:star, starrable: @repo)
      end
      star2 = Timecop.freeze(1.hour.ago) do
        create(:star, starrable: @repo)
      end

      assert_equal star2.id, domain.repository_latest_star(@repo.id)&.id
    end
  end

  context "repo_stars_not_spammy_for_viewer" do
    test "returns paginated star entities" do
      star3 = create(:star, user: @user, starrable: @repo)
      star1 = Timecop.travel(2.days.ago) { create(:star, user: create(:user), starrable: @repo) }
      star2 = Timecop.travel(1.day.ago) { create(:star, user: create(:user), starrable: @repo) }

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 1))
      assert_equal [star1], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 2, per_page: 1))
      assert_equal [star2], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 3, per_page: 1))
      assert_equal [star3], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30))
      assert_equal [star1, star2, star3], results.to_a
    end

    test "returns stars not spammy for the viewer", skip_unless: :spamminess_check_enabled? do
      spammer = create(:spammy_user)
      spammy_star = create(:star, user: spammer, starrable: @repo)
      not_spammy_star = create(:star, user: @user, starrable: @repo)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 30)

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: nil, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: spammer, pagination: pagination)
      assert_same_elements [spammy_star, not_spammy_star], results.to_a
    end

    test "returns ordered paginated star entities" do
      star3 = create(:star, user: @user, starrable: @repo)
      star1 = Timecop.travel(2.days.ago) { create(:star, user: create(:user), starrable: @repo) }
      star2 = Timecop.travel(1.day.ago) { create(:star, user: create(:user), starrable: @repo) }

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::ASC)])
      assert_equal [star1, star2, star3], results.to_a

      results = domain.repo_stars_not_spammy_for_viewer(@repo.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::DESC)])
      assert_equal [star3, star2, star1], results.to_a
    end
  end

  context "topic_stars_not_spammy_for_viewer" do
    test "returns paginated star entities" do
      star3 = create(:star, user: @user, starrable: @topic)
      star1 = Timecop.travel(2.days.ago) { create(:star, user: create(:user), starrable: @topic) }
      star2 = Timecop.travel(1.day.ago) { create(:star, user: create(:user), starrable: @topic) }

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 1))
      assert_equal [star1], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 2, per_page: 1))
      assert_equal [star2], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 3, per_page: 1))
      assert_equal [star3], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30))
      assert_equal [star1, star2, star3], results.to_a
    end

    test "returns stars not spammy for the viewer", skip_unless: :spamminess_check_enabled? do
      spammer = create(:spammy_user)
      spammy_star = create(:star, user: spammer, starrable: @topic)
      not_spammy_star = create(:star, user: @user, starrable: @topic)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 30)

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: nil, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: spammer, pagination: pagination)
      assert_same_elements [spammy_star, not_spammy_star], results.to_a
    end

    test "returns ordered paginated star entities" do
      star3 = create(:star, user: @user, starrable: @topic)
      star1 = Timecop.travel(2.days.ago) { create(:star, user: create(:user), starrable: @topic) }
      star2 = Timecop.travel(1.day.ago) { create(:star, user: create(:user), starrable: @topic) }

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::ASC)])
      assert_equal [star1, star2, star3], results.to_a

      results = domain.topic_stars_not_spammy_for_viewer(@topic.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::DESC)])
      assert_equal [star3, star2, star1], results.to_a
    end
  end

  context "gist_stars_not_spammy_for_viewer" do
    test "returns paginated star entities" do
      star3 = create(:gist_star, user: @user, gist: @gist)
      star1 = Timecop.travel(2.days.ago) { create(:gist_star, user: create(:user), gist: @gist) }
      star2 = Timecop.travel(1.day.ago) { create(:gist_star, user: create(:user), gist: @gist) }

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 1))
      assert_equal [star1], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 2, per_page: 1))
      assert_equal [star2], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 3, per_page: 1))
      assert_equal [star3], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30))
      assert_equal [star1, star2, star3], results.to_a
    end

    test "returns stars not spammy for the viewer", skip_unless: :spamminess_check_enabled? do
      spammer = create(:spammy_user)
      spammy_star = create(:gist_star, user: spammer, gist: @gist)
      not_spammy_star = create(:gist_star, user: @user, gist: @gist)

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 30)

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: nil, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: pagination)
      assert_equal [not_spammy_star], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: spammer, pagination: pagination)
      assert_same_elements [spammy_star, not_spammy_star], results.to_a
    end

    test "returns ordered paginated star entities" do
      star3 = create(:gist_star, user: @user, gist: @gist)
      star1 = Timecop.travel(2.days.ago) { create(:gist_star, user: create(:user), gist: @gist) }
      star2 = Timecop.travel(1.day.ago) { create(:gist_star, user: create(:user), gist: @gist) }

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::ASC)])
      assert_equal [star1, star2, star3], results.to_a

      results = domain.gist_stars_not_spammy_for_viewer(@gist.id, viewer: @user, pagination: GH::Pagination::Offset.new(page: 1, per_page: 30), sorts: [GH::Pagination::Sort.new(field: "created_at",  direction: GH::Pagination::Sort::Direction::DESC)])
      assert_equal [star3, star2, star1], results.to_a
    end
  end

  context "by_id" do
    test "returns the star with the given id" do
      s1 = create(:star, user: @user, starrable: create(:topic))

      result = domain.by_id(s1.id)
      assert_equal s1.id, result&.id
    end
  end

  context "by_ids" do
    test "returns the stars with the given ids" do
      s1 = create(:star, user: @user, starrable: create(:topic))
      s2 = create(:star, user: @user, starrable: create(:repository))

      results = domain.by_ids([s1.id, s2.id])
      assert_same_elements [s1, s2], results.to_a
    end
  end
end
