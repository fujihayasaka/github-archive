# typed: true
# frozen_string_literal: true

require "test_helper"

class StarTest < GitHub::TestCase
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @repo = create(:repository)
    @topic = create(:topic)
    @org  = create(:organization)

    @user    = create :user, email: "rtomayko@gmail.com"
    @mojombo = create(:user)
    @dewski  = create(:user)
    @defunkt = create(:user)
    @defunkt.star(@repo)
    @dewski.star(@repo)
    @user.follow(@mojombo)
    @user.follow(@defunkt)

    @team = create(:team, organization: @org)
    @team.add_member @user
  end

  context ".starred_repository_ids_from" do
    test "returns subset of given repo IDs that the user has starred" do
      unstarred_repo, unrequested_repo, repo_starred_by_other = create_list(:repository, 3)
      assert @defunkt.star(unrequested_repo)
      assert @user.star(repo_starred_by_other)
      all_repo_ids = [@repo.id, unstarred_repo.id, repo_starred_by_other.id]

      result = Star.starred_repository_ids_from(user: @defunkt, repository_ids: all_repo_ids)

      assert_includes result, @repo.id, "should include starred repo that was in given list"
      refute_includes result, unstarred_repo.id, "should not include unstarred repo"
      refute_includes result, unrequested_repo.id, "should not include starred repo that was not in given list"
      refute_includes result, repo_starred_by_other.id, "should not include repo starred by a different user"
      assert_equal 1, result.size
    end
  end

  context "User#can_star?" do
    test "user can star internal repositories they can see" do
      org1 = create(:enterprise_linked_organization)
      org2 = create(:organization, business: org1.business)
      internal_repo = create(:internal_repository, owner: org1)
      user = create(:user)
      org2.add_member(user)
      assert user.can_star?(internal_repo)
    end

    test "respects given is_readable=false flag" do
      assert @mojombo.can_star?(@repo)
      refute @mojombo.can_star?(@repo, is_readable: false)
    end

    test "respects given is_starred=true flag" do
      assert @mojombo.can_star?(@repo)
      refute @mojombo.can_star?(@repo, is_starred: true)
    end

    test "respects given is_starred=false flag" do
      refute @defunkt.can_star?(@repo)
      assert @defunkt.can_star?(@repo, is_starred: false)
    end
  end

  context ".from_following" do
    test "returns starred repos and topics based on stars of followed users" do
      @mojombo.star(@topic)

      actual = Star.from_following(@user).map { |star| [star.starrable_type, star.starrable_id] }
      expected = [
        ["Repository", @repo.id],
        ["Topic", @topic.id]
      ]

      assert_same_elements expected, actual
    end

    test "allows excluding specific topics from the result" do
      @mojombo.star(@topic)

      actual = Star.from_following(@user, { exclude_topics: [@topic.id] }).map { |star| [star.starrable_type, star.starrable_id] }
      expected = [
        ["Repository", @repo.id]
      ]

      assert_same_elements expected, actual
    end

    test "allows excluding specific repositories from the result" do
      @mojombo.star(@topic)

      actual = Star.from_following(@user, { exclude_repos: [@repo.id] }).map { |star| [star.starrable_type, star.starrable_id] }
      expected = [
        ["Topic", @topic.id]
      ]

      assert_same_elements expected, actual
    end

    test "allows specifying not to include any topics from results" do
      @mojombo.star(@topic)

      actual = Star.from_following(@user, include_topics: false).map { |star| [star.starrable_type, star.starrable_id] }
      assert_same_elements [["Repository", @repo.id]], actual
    end
  end

  context "star" do
    context "when the entity is a repository" do
      test "tracks the starred repository" do
        assert_difference "@user.stars.count", +1 do
          @user.star(@repo)
        end
      end

      test "instruments to hydro" do
        @user.star(@repo)
        repo_star = @user.stars.last
        @user.star(@topic)
        topic_star = @user.stars.last

        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          star_id: repo_star.id,
          action_type: :STAR,
          context_type: :OTHER,
          repository: Hydro::EntitySerializer.repository(@repo),
          repository_owner: Hydro::EntitySerializer.user(@repo.owner),
          repository_stars_count: @repo.stars.size,
          starred_at: repo_star.created_at,
        }, schema: "github.v1.RepositoryStar")
        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          star_id: topic_star.id,
          action_type: :STAR,
          context_type: :OTHER,
          topic: Hydro::EntitySerializer.topic(@topic),
          topic_stars_count: @topic.stars.size,
          starred_at: topic_star.created_at,
        }, schema: "github.v1.TopicStar")
      end

      test "can't star an repository twice" do
        assert @user.star(@repo), "should be true"
        refute @user.star(@repo), "repo is already starred by user"
      end

      test "requires the user to have a verified email" do
        GitHub.stubs(:mandatory_email_verification_enabled?).returns(true)
        @user.require_email_verification!
        star = Star.create(user: @user, starrable: @repo)
        refute star.valid?
        assert_equal ["At least one email address must be verified to do that"], star.errors[:base]
      end if GitHub.email_verification_enabled?

      test "can't star the repo of a user that has blocked you" do
        blocker = create :user
        repo = create :repository, owner: blocker
        blocker.block(@user)

        star = Star.create(user: @user, starrable: repo)
        refute star.valid?
        assert_equal ["You can't perform that action at this time"], star.errors[:base]
      end if GitHub.user_abuse_mitigation_enabled?

      test "can't star a repo that isn't visible to you" do
        private_repo = create(:private_repository)
        assert !private_repo.readable_by?(@user)

        star = Star.create(user: @user, starrable: private_repo)
        refute star.valid?
        assert_equal ["You can't perform that action at this time"], star.errors[:base]
      end

      test "updates the stargazer count" do
        assert_difference "@repo.stargazer_count" do
          @user.star(@repo)
        end
      end

      test "instruments star.create" do
        events = subscribe "star.create"

        @user.star(@repo)

        expected_payload = {
          spammy: false,
          allowed: false,
          star_id: T.must(Star.last).id,
          public_repo: @repo.public?,
          action: :created,
          starred: @repo.name_with_owner,
          starred_id: @repo.id,
          starred_type: "Repository",
          user: @user.login,
          user_id: @user.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "when the entity is a topic" do
      test "tracks the starred topic" do
        assert_difference "@user.stars.count", +1 do
          @user.star(@topic)
        end
      end

      test "can't star an topic twice" do
        assert @user.star(@topic), "should be true"
        refute @user.star(@topic), "topic is already starred by user"
      end

      test "instruments star.create" do
        events = subscribe "star.create"

        @user.star(@topic)

        expected_payload = {
          spammy: false,
          allowed: false,
          star_id: T.must(Star.last).id,
          action: :created,
          starred: @topic.name,
          starred_type: "Topic",
          starred_id: @topic.id,
          user: @user.login,
          user_id: @user.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end


    if GitHub.spamminess_check_enabled?
      test "not_spammy gets stars from non spammy users" do
        perform_enqueued_jobs(only: UpdateTableUserHiddenJob) do
          assert_equal 2, Star.not_spammy.count
          @defunkt.mark_as_spammy
          assert_equal 1, Star.not_spammy.count
        end
      end
    end
  end

  context "unstar" do
    context "when the entity is a repository" do
      test "unstarring removes a count from the repository's stars" do
        @user.star(@repo)

        assert_difference "@user.stars.count", -1 do
          @user.unstar(@repo)
        end
      end

      test "updates the repository's stargazer count" do
        @user.star(@repo)

        assert_difference "@repo.reload.stargazer_count", -1 do
          @user.unstar(@repo)
        end
      end

      test "removes the repository from any user lists" do
        @user.star(@repo)

        create(:user_list, user: @user).tap do |list|
          create(:user_list_item, user_list: list, repository: @repo)
        end

        assert_changes -> { @user.has_list_with_item?(@repo) }, from: true, to: false do
          @user.unstar(@repo)
        end
      end

      test "instruments star.destroy" do
        @user.star(@repo)
        star_id = T.must(Star.last).id

        events = subscribe "star.destroy"

        @user.unstar(@repo)

        expected_payload = {
          spammy: false,
          allowed: false,
          star_id: star_id,
          public_repo: @repo.public?,
          action: :deleted,
          starred: @repo.name_with_owner,
          starred_id: @repo.id,
          starred_type: "Repository",
          user: @user.login,
          user_id: @user.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context "when the entity is a topic" do
      test "unstarring removes a count from the topic's stars" do
        @user.star(@topic)

        assert_difference "@user.stars.count", -1 do
          @user.unstar(@topic)
        end
      end

      test "instruments star.destroy" do
        @user.star(@topic)
        star_id = T.must(Star.last).id

        events = subscribe "star.destroy"

        @user.unstar(@topic)

        expected_payload = {
          allowed: false,
          spammy: false,
          starred: @topic.name,
          starred_id: @topic.id,
          starred_type: "Topic",
          user: @user.login,
          user_id: @user.id,
          star_id: star_id,
          action: :deleted,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end

  context "friends" do
    test "finds within period" do
      star = Star.where(user_id: @defunkt.id, starrable_id: @repo.id).first
      assert_equal [@defunkt], @user.following_starred(T.must(star).starrable_id, "daily")

      T.must(star).update(created_at: 1.month.ago)
      assert @user.following_starred(T.must(star).starrable_id, "daily").empty?
    end
  end

  context "#for_topic?" do
    test "returns true when the star is for a Topic" do
      star = create(:star, starrable: create(:topic))

      assert star.for_topic?
    end

    test "returns false when the star is for a Repository" do
      star = create(:star, starrable: create(:repository))

      refute star.for_topic?
    end
  end

  context "#for_repository?" do
    test "returns true when the star is for a Repository" do
      star = create(:star, starrable: create(:repository))

      assert star.for_repository?
    end

    test "returns false when the star is for a Topic" do
      star = create(:star, starrable: create(:topic))

      refute star.for_repository?
    end
  end

  context "#public_starrable?" do
    test "returns false when the starrable has been deleted" do
      repo = create(:repository)
      star = create(:star, starrable: repo)
      repo.destroy

      refute_predicate star.reload, :public_starrable?
    end

    test "returns true for topics and public repos" do
      repo_star = create(:star, starrable: create(:repository))
      topic_star = create(:star, starrable: create(:topic))

      assert_predicate repo_star, :public_starrable?
      assert_predicate topic_star, :public_starrable?
    end

    test "returns false for private repos" do
      user = create(:user)
      star = create(:star, user: user, starrable: create(:private_repository, owner: user))

      refute_predicate star, :public_starrable?
    end
  end

  test "gets deleted with repository" do
    repo_star = create(:star, starrable: create(:public_repository))
    topic_star = create(:star, starrable: create(:topic))

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo_star.starrable
      config.expect_destroyed = [repo_star]
      config.expect_not_destroyed = [topic_star]
      config.gated_by = GitHub.flipper[:purge_stars_in_background].enabled?
    end
  end
end
