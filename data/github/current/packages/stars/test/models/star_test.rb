# typed: true
# frozen_string_literal: true

require "test_helper"

class StarTest < GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
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
          repository_stars_count: Stars.domain.repository_star_count(@repo.id),
          starred_at: repo_star.created_at,
        }, schema: "github.v1.RepositoryStar")
        assert_hydro_published({
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(@user),
          star_id: topic_star.id,
          action_type: :STAR,
          context_type: :OTHER,
          topic: Hydro::EntitySerializer.topic(@topic),
          topic_stars_count: Stars.domain.topic_star_count(@topic.id),
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

        @user.star(@repo, context: "user_list")

        expected_payload = {
          spammy: false,
          allowed: false,
          star_id: T.must(Star.last).id,
          public_repo: @repo.public?,
          action: :created,
          context: "user_list",
          starred: @repo.name_with_owner,
          starred_id: @repo.id,
          starred_type: "Repository",
          user: @user.login,
          user_id: @user.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "creates a Stratocaster event" do
        assert_enqueued_with(job: ProcessEventJob, args: ["WatchEvent", [@repo.id, @user.id, :started, "Repository"]]) do
          @user.star(@repo)
        end
      end

      test "does not create a Stratocaster event when the star is created by automated recovery process" do
        enable_feature_flag(:skip_recovery_stars_stratocaster)

        assert_no_enqueued_jobs(only: [ProcessEventJob]) do
          @user.star(@repo, context: "recovery")
        end
      end

      test "creates a Stratocaster event when a recovery star is created when the flag is disabled" do
        disable_feature_flag(:skip_recovery_stars_stratocaster)

        assert_enqueued_with(job: ProcessEventJob, args: ["WatchEvent", [@repo.id, @user.id, :started, "Repository"]]) do
          @user.star(@repo, context: "recovery")
        end
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
          context: "other",
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
          context: "other",
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
          context: "other",
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

  context "member removed from repo" do
    test "unstars a private repo" do
      pj = create(:user)
      ambition = create(:private_repository)
      ambition.add_member(pj)
      Stars.domain.star_repository(repository: ambition, user: pj)

      assert Stars.domain.repo_starred_by_user?(ambition.id, pj.id)
      only = [RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        ambition.remove_member(pj)
      end
      refute Stars.domain.reset_caches.repo_starred_by_user?(ambition.id, pj.id)
    end

    test "stays starred when removing self" do
      pj = create(:user)
      facebox = create(:public_repository)
      facebox.add_member(pj)
      Stars.domain.star_repository(repository: facebox, user: pj)

      assert Stars.domain.repo_starred_by_user?(facebox.id, pj.id)
      facebox.remove_member(pj, pj)
      assert Stars.domain.reset_caches.repo_starred_by_user?(facebox.id, pj.id)
    end
  end

  context "transfering repository" do
    test "new owner doesn't star the repo" do
      user = create(:user)
      repo = create(:public_repository, owner: user)
      org = create(:organization)

      refute Stars.domain.repo_starred_by_user?(repo.id, org.id)
      repo.transfer_ownership_to(org, actor: user)
      refute Stars.domain.repo_starred_by_user?(repo.id, org.id)
    end

    test "forces users to unstar private repos when transferred to an org" do
      user = create(:user)
      user3 = create(:user)
      private_repo = create(:private_repository, owner: user)
      org = create(:organization, admin: user)
      private_repo.add_member(user3)

      # @user is a collab and on the Owners team
      # @user3 is a collab, but not on the Owners team
      Stars.domain.star_repository(repository: private_repo, user: user)
      Stars.domain.star_repository(repository: private_repo, user: user3)

      assert private_repo.members.include?(user3)
      assert Stars.domain.repo_starred_by_user?(private_repo.id, user3.id)
      private_repo.transfer_ownership_to org, actor: user

      assert Stars.domain.reset_caches.repo_starred_by_user?(private_repo.id, user.id)
    end

    test "does nothing for public stargazers when transferred to an org" do
      user = create(:user)
      user3 = create(:user)
      repo = create(:public_repository, owner: user)
      org = create(:organization)
      repo.add_member(user3)

      Stars.domain.star_repository(repository: repo, user: user)
      Stars.domain.star_repository(repository: repo, user: user3)

      assert repo.members.include?(user3)
      assert Stars.domain.repo_starred_by_user?(repo.id, user3.id)
      repo.transfer_ownership_to org, actor: user

      assert Stars.domain.reset_caches.repo_starred_by_user?(repo.id, user.id)
      assert Stars.domain.reset_caches.repo_starred_by_user?(repo.id, user3.id)
    end
  end

  test "gets deleted with repository" do
    repo_star = create(:star, starrable: create(:public_repository))
    topic_star = create(:star, starrable: create(:topic))

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = repo_star.starrable
      config.expect_destroyed = [repo_star]
      config.expect_not_destroyed = [topic_star]
    end
  end

  context "Setting the visibility of a public repo to private" do
    test "stops non-members from starring" do
      @maddox = create(:user)
      @rtomayko = create(:user)
      @simple = create(:repository, name: "simple", owner: @rtomayko)

      Stars.domain.star_repository(repository: @simple, user: @maddox)
      Stars.domain.star_repository(repository: @simple, user: @rtomayko)
      assert Stars.domain.repo_starred_by_user?(@simple.id, @maddox.id)
      perform_enqueued_hydro_jobs(only: [HydroStarsRepositoryVisibilityJob]) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          @simple.set_visibility(actor: @simple.owner, visibility: "private")
        end
      end
      assert_predicate @simple.reload, :private?
      assert Stars.domain.reset_caches.repo_starred_by_user?(@simple.id, @rtomayko.id)
      refute Stars.domain.reset_caches.repo_starred_by_user?(@simple.id, @maddox.id)
    end
  end

  context "Setting the visibility of a public repo to internal" do
    test "stops non-members from starring" do
      @maddox = create(:user)
      @rtomayko = create(:user)
      @biz_org_admin = create(:user)
      @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@rtomayko], seats: 20)
      @business = create(:business, owners: [@biz_org_admin], organizations: [@biz_org], seats: 20)
      @biz_org.update!(business: @business)
      @biz_org.allow_private_repository_forking(actor: @biz_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      @biz_simple = create(:repository, name: "biz-simple", owner: @biz_org)

      Stars.domain.star_repository(repository: @biz_simple, user: @maddox)
      Stars.domain.star_repository(repository: @biz_simple, user: @rtomayko)
      assert Stars.domain.repo_starred_by_user?(@biz_simple.id, @maddox.id)
      perform_enqueued_hydro_jobs(only: [HydroStarsRepositoryVisibilityJob]) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          @biz_simple.set_visibility(actor: @biz_org_admin, visibility: "internal")
        end
      end
      assert_predicate @biz_simple.reload, :internal?
      assert Stars.domain.reset_caches.repo_starred_by_user?(@biz_simple.id, @rtomayko.id)
      refute Stars.domain.reset_caches.repo_starred_by_user?(@biz_simple.id, @maddox.id)
    end
  end
end
