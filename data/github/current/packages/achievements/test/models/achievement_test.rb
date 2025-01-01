# typed: true
# frozen_string_literal: true

require "test_helper"

class AchievementTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:verified_user)

    @repo = create(:repository, from_example: :simple)
  end

  context "validations" do
    test "it validates the presence of the user" do
      achievement = create(:achievement, :pull_shark)
      achievement.user = nil

      achievement.validate

      assert_includes achievement.errors[:user], "can't be blank"
    end

    test "it validates the presence of the unlocking model" do
      achievement = create(:achievement, :pull_shark)
      achievement.unlocking_model = nil

      achievement.validate

      assert_includes achievement.errors[:unlocking_model], "can't be blank"
    end

    test "it validates the absence of an unlocking model for achievables with a dynamic unlocking model spec" do
      achievement = create(:achievement, :mars_2020_contributor)
      achievement.unlocking_model = create(:repository)

      achievement.validate

      assert_includes achievement.errors[:unlocking_model], "is Repository, can't be provided for Mars 2020 Contributor"
    end

    test "it validates the correctness of the unlocking model type against an achievable with an exact requirement" do
      achievement = create(:achievement, :pull_shark)
      achievement.unlocking_model = create(:issue)

      achievement.validate

      assert_includes achievement.errors[:unlocking_model], "is Issue, not one of the expected types PullRequest"
    end

    test "it validates the correctness of the unlocking model type against an achievable with a pattern requirement" do
      achievement = create(:achievement, :heart_on_your_sleeve)
      achievement.unlocking_model = create(:repository)

      achievement.validate

      assert_includes achievement.errors[:unlocking_model],
        "is Repository, not one of the expected types " +
        ::Achievable::UnlockingModelSpec::Reactable.new.accepted_types.join(", ")
    end

    test "it validates the correctness of a dynamic unlocking model type" do
      achievement = create(:achievement, :arctic_code_vault_contributor)
      achievement.unlocking_model = create(:repository)

      achievement.validate

      assert_includes achievement.errors[:unlocking_model],
        "is Repository, can't be provided for Arctic Code Vault Contributor"
    end

    test "it validates the presence of an unlocking oid if the achievable requires one" do
      achievement = create(:achievement, :dust_bunny)
      achievement.unlocking_oid = nil

      achievement.validate

      assert_includes achievement.errors[:unlocking_oid], "can't be blank"
    end

    test "it validates that a user can't have multiple achievements with the same tier, slug, and visibility" do
      create(:achievement, :pull_shark, user: @user, tier: 0, visibility: :public_scope)
      achievement = build(
        :achievement,
        :pull_shark,
        user: @user,
        tier: 0,
        visibility: :public_scope,
      )

      achievement.validate

      assert_includes achievement.errors[:achievable_slug], "has already been taken"
    end

    test "it validates the presence of an achievable slug" do
      achievement = create(:achievement, :pull_shark)
      achievement.achievable_slug = nil

      achievement.validate

      assert_includes achievement.errors[:achievable_slug], "can't be blank"
    end

    test "it validates that the achievable_slug is a known slug" do
      achievement = build(:achievement, achievable_slug: "unknown")

      achievement.validate

      assert_includes achievement.errors[:achievable_slug], "is not included in the list"
    end

    test "it validates the presence of the tier" do
      achievement = create(:achievement, :pull_shark)
      achievement.tier = nil

      achievement.validate

      assert_includes achievement.errors[:tier], "can't be blank"
    end

    test "it validates that tier is included in the achievable tiers" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 1, Achievable::PullShark),
      ])

      achievement = create(:achievement, :pull_shark)
      achievement.tier = 2

      achievement.validate

      assert_includes achievement.errors[:tier], "is not included in the achievable tiers"
    end
  end

  context "scopes" do
    context ".with_slug" do
      test "it returns achievements with the given slug" do
        pull_shark = create(:achievement, :pull_shark)
        pair_extraordinaire = create(:achievement, :pair_extraordinaire)

        assert_includes Achievement.with_slug(pull_shark.achievable_slug), pull_shark
        refute_includes Achievement.with_slug(pull_shark.achievable_slug), pair_extraordinaire
      end
    end

    context ".with_tier" do
      test "it returns achievements with the given tier" do
        tier_1_achievement = create(:achievement, :pull_shark, tier: 1)
        tier_2_achievement = create(:achievement, :pull_shark, tier: 2)

        assert_includes Achievement.with_tier(1), tier_1_achievement
        refute_includes Achievement.with_tier(1), tier_2_achievement
      end
    end

    context ".with_visibility" do
      test "it returns achievements with the given visibility" do
        public_achievement = create(:achievement, :pull_shark, visibility: :public_scope)
        private_achievement = create(:achievement, :pull_shark, visibility: :private_scope)

        assert_includes Achievement.with_visibility(:PUBLIC), public_achievement
        refute_includes Achievement.with_visibility(:PUBLIC), private_achievement
      end
    end

    context ".unseen" do
      test "it returns achievements that do not have a seen_at timestamp" do
        seen_achievement = create(:achievement, :pull_shark, seen_at: Time.now)
        first_unseen_achievement = create(:achievement, :pair_extraordinaire, seen_at: nil)
        second_unseen_achievement = create(:achievement, :dust_bunny, seen_at: nil)

        assert_includes Achievement.unseen, first_unseen_achievement
        assert_includes Achievement.unseen, second_unseen_achievement
        refute_includes Achievement.unseen, seen_achievement
      end
    end
  end

  context "#safe_user" do
    test "returns the owning user" do
      ach = create(:achievement, :pull_shark, user: @user)
      assert_equal @user, ach.safe_user
    end

    test "returns ghost if the owning user has been deleted" do
      ach = create(:achievement, :pull_shark, user: @user)
      ach.user = nil
      assert_equal User.ghost, ach.safe_user
    end
  end

  context "#achievable" do
    test "it returns the proper achievable associated with the achievement" do
      dust_bunny_achievement = create(:achievement, :dust_bunny, user: @user)
      heartbreaker_achievement = create(:achievement, :heartbreaker, user: @user)

      assert_instance_of Achievable::DustBunny, dust_bunny_achievement.achievable
      assert_instance_of Achievable::Heartbreaker, heartbreaker_achievement.achievable
    end

    test "it associates the correct unlocking model with the achievement" do
      dust_bunny_achievement = create(:achievement, :dust_bunny, user: @user)
      heartbreaker_achievement = create(:achievement, :heartbreaker, user: @user)

      assert_instance_of Repository, dust_bunny_achievement.unlocking_model
      assert_instance_of Issue, heartbreaker_achievement.unlocking_model
    end
  end

  context "#description_template" do
    test "returns the description template of the achievable at the current tier" do
      Achievable::PullShark.stubs(:defined_tiers).returns([
        Achievable::Tier.new(0, 10, Achievable::PullShark),
        Achievable::Tier.new(1, 20, Achievable::PullShark),
      ])

      achievement0 = create(:achievement, :pull_shark, user: @user, tier: 0)
      assert_equal "%{achieving_user_login} opened pull requests that have been merged.",
        achievement0.description_template

      achievement1 = create(:achievement, :pull_shark, user: @user, tier: 1)
      assert_equal "%{achieving_user_login} opened pull requests that have been merged.",
        achievement1.description_template
    end
  end

  context "#unlocking_explanation_template" do
    test "returns the unlocking explanation of the associated achievable" do
      achievement = create(:achievement, :dust_bunny, user: @user)

      assert_equal "Commit message contains \"linter\"", achievement.unlocking_explanation_template
    end
  end

  context "#unlocking_model and #async_unlocking_model" do
    test "returns the relation normally for most achievements" do
      achievement = create(:achievement, :starstruck, user: @user, unlocking_model: @repo)
      assert_equal @repo, achievement.unlocking_model
      assert_equal @repo, achievement.async_unlocking_model.sync
    end

    test "retrieves a memoized list of top ACV contributions for the ACV achievement" do
      create(:user_metadata, user: @user, has_acv_badge: true)

      email = @user.emails.take!
      contributions = create_list(:acv_contributor, 5, contributor_email: email) do |contribution, i|
        contribution.repository.update!(stargazer_count: i)
      end
      expected_repos = [4, 3, 2, 1].map { |i| contributions[i].repository }

      achievement = create(:achievement, :arctic_code_vault_contributor, user: @user)

      assert_equal expected_repos, achievement.unlocking_model.repositories
      assert_no_queries do
        assert_equal expected_repos, achievement.unlocking_model.repositories
        assert_equal expected_repos, achievement.async_unlocking_model.sync.repositories
      end
    end

    test "retrieves a memoized list of Mars Rover contributions for the Mars 2020 achievement" do
      email = @user.emails.take!
      highlight = create(:profile_highlight, user: @user, highlight_type: :nasa_2020, hidden: false, eligible: true)

      contributions = create_list(:profile_highlight_contribution, 5,
        profile_highlight: highlight, contributor_email: email
      ) do |contribution, i|
        contribution.repository.update!(stargazer_count: i)
      end
      expected_repos = [4, 3, 2, 1].map { |i| contributions[i].repository }

      achievement = create(:achievement, :mars_2020_contributor, user: @user)

      assert_equal expected_repos, achievement.unlocking_model.repositories
      assert_no_queries do
        assert_equal expected_repos, achievement.unlocking_model.repositories
        assert_equal expected_repos, achievement.async_unlocking_model.sync.repositories
      end
    end
  end

  context "#unlocking_commit" do
    test "returns nil when the achievement has no unlocking oid" do
      achievement = create(:achievement, :pull_shark, user: @user)

      assert_nil achievement.unlocking_commit
    end

    test "returns nil when the unlocking repository is not found" do
      achievement = build(:achievement, :dust_bunny, user: @user, unlocking_model: nil)

      assert_nil achievement.unlocking_commit
    end

    test "returns nil when the unlocking oid is not valid" do
      achievement = build(:achievement, :dust_bunny, user: @user, unlocking_oid: "0" * 40)

      assert_nil achievement.unlocking_commit
    end

    test "returns nil when the GitRPC call times out" do
      @repo.commits.stubs(:find).raises(GitRPC::Timeout)
      achievement = create(:achievement, :dust_bunny, user: @user, unlocking_model: @repo)

      assert_nil achievement.unlocking_commit
    end

    test "returns a Commit when achievement has an unlocking oid" do
      achievement = create(:achievement, :dust_bunny,
        user: @user, unlocking_model: @repo, unlocking_oid: @repo.default_oid)

      commit = achievement.unlocking_commit
      assert_equal @repo.default_oid, commit.oid
    end
  end

  context "#unlocking_model_owner_opted_out?" do
    test "returns true if the User or Organization associated with a private unlocking model has opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = true
      model = create(:issue, repository: create(:private_repository, owner: owner))
      achievement = create(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false if the User or Organization associated with a public unlocking model has opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = true
      model = create(:issue, repository: create(:repository, owner: owner))
      achievement = create(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false if the User or Organization associated with a private unlocking model has not opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = false
      model = create(:issue, repository: create(:private_repository, owner: owner))
      achievement = create(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns true if the User or Organization associated with a private repository has opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = true
      model = create(:private_repository, owner: owner)
      achievement = create(:achievement, :starstruck, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false if the User or Organization associated with a public repository has opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = true
      model = create(:repository, owner: owner)
      achievement = create(:achievement, :starstruck, unlocking_model: model)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false if the User or Organization associated with a private repository has not opted out" do
      owner = create(:user)
      owner.profile_settings.all_private_projects_opted_out_of_achievements_tracking = false
      model = create(:private_repository, owner: owner)
      achievement = create(:achievement, :starstruck, unlocking_model: model)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns true when a repo is nil" do
      model = build(:issue, repository: nil)
      achievement = build(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns true when a repo's owner is nil" do
      repo = build(:private_repository, owner: nil)
      model = build(:issue, repository: repo)
      achievement = build(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns true if the owner of a repoless unlocking model has opted out" do
      org = create(:organization)
      org.profile_settings.all_private_projects_opted_out_of_achievements_tracking = true
      model = create(:discussion_post, team: create(:team, organization: org))
      achievement = create(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false if the owner of a repoless unlocking model has not opted out" do
      org = create(:organization)
      org.profile_settings.all_private_projects_opted_out_of_achievements_tracking = false
      model = create(:discussion_post, team: create(:team, organization: org))
      achievement = create(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns true when a step along the owner path is nil" do
      model = build(:discussion_post_reply, team: nil, user: @user)
      achievement = build(:achievement, :heart_on_your_sleeve, unlocking_model: model)

      assert_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "returns false when the unlocking model type has no owner" do
      achievement = build(:achievement, :public_sponsor)

      refute_predicate achievement, :unlocking_model_owner_opted_out?
    end

    test "logic covers all supported unlocking model types" do
      all_known_types = Achievable.all_known.flat_map(&:accepted_unlocking_model_types).to_set
      missing_types = all_known_types -
        Achievement::UNLOCKING_MODEL_REPO_RELATIONS.keys -
        Achievement::UNLOCKING_MODEL_OWNER_RELATIONS.keys -
        Achievement::UNLOCKING_MODEL_OWNERLESS

      assert_empty missing_types,
        "UNLOCKING_MODEL_OWNER_RELATIONS does not include all known unlocking model types"
    end
  end

  context "#unseen? and #seen?" do
    test "returns true if the achievement has not been seen by the user" do
      achievement = create(:achievement, :dust_bunny, user: @user, seen_at: nil)
      assert_predicate achievement, :unseen?
      refute_predicate achievement, :seen?
    end

    test "returns false if the achievement has been seen by the user" do
      achievement = create(:achievement, :dust_bunny, user: @user, seen_at: Time.now)
      refute_predicate achievement, :unseen?
      assert_predicate achievement, :seen?
    end
  end

  context "#highest_tier_achievement" do
    test "returns the highest tier achievement for this achievable, user and visibility" do
      ach0 = create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 0)
      ach1 = create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 1)
      ach2 = create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 2)

      # Red herrings to make the queries interesting
      create(:achievement, :heart_on_your_sleeve, :private_scope, user: @user, tier: 3)
      create(:achievement, :pull_shark, :public_scope, user: @user, tier: 3)
      create(:achievement, :heart_on_your_sleeve, :public_scope, tier: 3)

      assert_equal ach2, ach0.highest_tier_achievement
      assert_equal ach2, ach1.highest_tier_achievement
      assert_equal ach2, ach2.highest_tier_achievement
    end

    test "returns self if this is the highest possible tier achievement" do
      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 0)
      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 1)
      create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 2)
      ach = create(:achievement, :heart_on_your_sleeve, :public_scope, user: @user, tier: 3)

      assert_no_queries do
        assert_equal ach, ach.highest_tier_achievement
      end
    end
  end

  context "#to_slug_and_tier" do
    test "returns the concatenated Achievable slug and tier of the achievement" do
      assert_equal "pull-shark:2", create(:achievement, :pull_shark, tier: 2).to_slug_and_tier
    end

    test "uses tier 0 for single-tier achievements" do
      assert_equal "dust-bunny:0", create(:achievement, :dust_bunny).to_slug_and_tier
    end
  end

  context "Hydro instrumentation" do
    test "emits an AchievementUnlock event when an achievement is created" do
      user = create(:user)
      achievement = create(:achievement, :pull_shark, user: user, tier: 2, visibility: :private_scope)

      message = {
        user: Hydro::EntitySerializer.user(user),
        achievable: "PULL_SHARK",
        tier: achievement.tier,
        visibility: :PRIVATE,
      }

      assert_hydro_published(message, schema: "github.achievements.v1.AchievementUnlock")
      assert_hydro_messages(count: 1, schema: "github.achievements.v1.AchievementUnlock")
    end
  end

  context "#unlocked_at" do
    test "returns the unlocked_at timestamp on the achievement record" do
      unlocked_at = DateTime.parse("2019-01-01")
      achievement = create(
        :achievement,
        :pull_shark,
        user: @user,
        tier: 2,
        unlocked_at: unlocked_at,
      )

      assert_equal unlocked_at, achievement.unlocked_at
    end
  end
end
