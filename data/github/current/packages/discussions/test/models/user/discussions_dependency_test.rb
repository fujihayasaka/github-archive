# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionsDependencyTest < GitHub::TestCase
  include DiscussionsTestHelper

  fixtures do
    create_discussions_authz_fixtures
  end

  setup do
    @matrix = AccessMatrix.new(self)
    @matrix.setup_user_subjects
  end

  context "#copilot_discussion_summary_feature_enabled?" do
    test "returns true when user is explicitly in the flag" do
      @rando.enable_feature(:discussions_copilot_summary)
      assert_predicate @rando, :copilot_discussion_summary_feature_enabled?
    end

    test "returns false when flag is fully disabled" do
      GitHub.flipper[:discussions_copilot_summary].disable
      refute_predicate @rando, :copilot_discussion_summary_feature_enabled?
    end

    test "returns true when user belongs to an org in the feature flag" do
      @org.enable_feature(:discussions_copilot_summary)
      assert_predicate @org_member, :copilot_discussion_summary_feature_enabled?
    end
  end

  context "#can_manage_discussion_spotlights?" do
    test "requires write+ for users" do
      @matrix.user_scenarios(
        :can_manage_discussion_spotlights?,
        none: false,
        read: false,
        triage: false,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false when repo has discussions off" do
      @matrix.each_repo { |repo, owner| repo.turn_off_discussions(actor: owner, instrument: false) }

      @matrix.user_scenarios(
        :can_manage_discussion_spotlights?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    if GitHub.email_verification_enabled?
      test "false for user without a verified email address" do
        @owner.emails.map(&:unverify!)

        refute @owner.can_manage_discussion_spotlights?(@repo)
      end
    else
      test "true for user without a verified email address" do
        @owner.emails.map(&:unverify!)

        assert @owner.can_manage_discussion_spotlights?(@repo)
      end
    end
  end

  context "#can_create_discussion_spotlight?" do
    test "false when user cannot manage spotlights" do
      User.any_instance.stubs(:can_manage_discussion_spotlights?).returns(false)

      refute @owner.can_create_discussion_spotlight?(@repo)
    end

    test "true when repo not at spotlight limit and user can manage spotlights" do
      assert @owner.can_create_discussion_spotlight?(@repo)
    end

    test "false when user can manage spotlights but repo has max amount of spotlights" do
      DiscussionSpotlight.stub_const(:LIMIT_PER_REPOSITORY, 1) do
        create(:discussion_spotlight, repository: @repo)
        refute @owner.can_create_discussion_spotlight?(@repo)
      end
    end
  end

  context "#can_create_discussion? and #async_can_create_discussion?" do
    test "requires read+ for users" do
      @matrix.user_scenarios(
        :can_create_discussion?,
        none: false,
        read: true,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "requires triage+ for users on repo with explicit permission required" do
      [
        @org,
        @business_org,
        @business_org_two,
        @org_without_default_permission,
        @business_org,
        @business_org_two,
      ].each do |org|
        org.block_readers_from_creating_discussions(actor: @org_admin)
      end

      assert_block = lambda do |user, repo|
        assert user.can_create_discussion?(repo)
        assert user.async_can_create_discussion?(repo).sync
      end

      refute_block = lambda do |user, repo|
        refute user.can_create_discussion?(repo)
        refute user.async_can_create_discussion?(repo).sync
      end

      @matrix.users_without_access(&refute_block)
      @matrix.users_with_triage_access(&assert_block)
      @matrix.users_with_write_access(&assert_block)
      @matrix.users_with_maintain_access(&assert_block)
      @matrix.users_with_admin_access(&assert_block)

      @matrix.users_with_read_access do |user, repo|
        if repo.in_organization?
          refute_block.call(user, repo)
        else
          assert_block.call(user, repo)
        end
      end
    end

    test "false for private org-owned repo with default repo permissions :none and user is an org member" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org_admin)
      end

      refute @org_member.can_create_discussion?(@org_private_repo)
      refute @org_member.async_can_create_discussion?(@org_private_repo).sync
    end

    test "true for private org-owned repo for org admin with default repository permissions :none" do
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        @org.update_default_repository_permission(:none, actor: @org_admin)
      end

      assert @org_admin.can_create_discussion?(@org_private_repo)
      assert @org_admin.async_can_create_discussion?(@org_private_repo).sync
    end

    test "false when discussions are turned off" do
      @matrix.each_repo { |repo, owner| repo.turn_off_discussions(actor: owner, instrument: false) }

      @matrix.user_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repository is archived" do
      @matrix.each_repo { |repo| repo.set_archived }

      @matrix.user_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repo is locked" do
      @matrix.each_repo { |repo| repo.lock_for_migration }

      @matrix.user_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false for user blocked by repo owner" do
      @owner.block(@rando)
      refute @rando.can_create_discussion?(@repo)
      refute @rando.async_can_create_discussion?(@repo).sync
    end

    if GitHub.email_verification_enabled?
      test "false for user who doesn't have verified email address" do
        refute @unverified.can_create_discussion?(@repo)
        refute @unverified.async_can_create_discussion?(@repo).sync
      end

      test "true for user who has more than one verified email address" do
        create(:user_email, :verified, user: @rando)
        assert @rando.can_create_discussion?(@repo)
        assert @rando.async_can_create_discussion?(@repo).sync
      end
    else
      test "true for user who doesn't have verified email address" do
        assert @unverified.can_create_discussion?(@repo)
        assert @unverified.async_can_create_discussion?(@repo).sync
      end
    end

    if GitHub.interaction_limits_enabled?
      test "when repository has no temporary ability locks allows rando user" do
        assert @rando.can_create_discussion?(@org_repo)
        assert @rando.async_can_create_discussion?(@org_repo).sync
      end

      test "when repository has temporarily restricted access restricts rando user" do
        ability = RepositoryInteractionAbility.new(@org)

        ability.set_ability(:collaborators_only, @org.admin)

        refute @rando.can_create_discussion?(@org_repo)
        refute @rando.async_can_create_discussion?(@org_repo).sync
      end

      test "when repository has temporarily restricted access allows collaborator" do
        @org_repo.add_member(@rando)

        ability = RepositoryInteractionAbility.new(@org)
        ability.set_ability(:collaborators_only, @org.admin)

        assert @rando.can_create_discussion?(@org_repo)
        assert @rando.async_can_create_discussion?(@org_repo).sync
      end
    end

    test "requires discussions: write for integrations" do
      @matrix.bot_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        write: true,
      )
    end

    test "disallows integrations when repo is locked" do
      @matrix.each_repo { |repo| repo.lock_for_migration }

      @matrix.bot_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        write: false,
      )
    end

    test "disallows integrations when repo is archived" do
      @matrix.each_repo { |repo| repo.set_archived }

      @matrix.bot_scenarios(
        :can_create_discussion?,
        none: false,
        read: false,
        write: false,
      )
    end
  end

  context "#can_create_discussion_category?" do
    test "requires triage+ for users" do
      @matrix.user_scenarios(
        :can_create_discussion_category?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "false for user blocked by repo owner" do
      @org_repo.owner.block(@writer)
      refute @writer.can_create_discussion_category?(@org_repo)
    end

    test "false when repo is archived" do
      @matrix.each_repo { |repo| repo.set_archived }

      @matrix.user_scenarios(
        :can_create_discussion_category?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end

    test "false when repo is locked" do
      @matrix.each_repo { |repo| repo.lock_for_migration }

      @matrix.user_scenarios(
        :can_create_discussion_category?,
        none: false,
        read: false,
        triage: false,
        write: false,
        maintain: false,
        admin: false,
      )
    end
  end

  context "#has_dismissed_discussions_announcement?" do
    test "is false to begin with" do
      refute_predicate @owner, :has_dismissed_discussions_announcement?
    end

    test "is true once #dismiss_discussions_announcement has been called" do
      @owner.dismiss_discussions_announcement

      assert_predicate @owner, :has_dismissed_discussions_announcement?
    end
  end

  context "#has_dismissed_discussions_private_repo_announcement?" do
    test "is false to begin with" do
      refute_predicate @owner, :has_dismissed_discussions_private_repo_announcement?
    end

    test "is true once #dismiss_discussions_announcement has been called" do
      @owner.dismiss_private_repo_discussions_announcement

      assert_predicate @owner, :has_dismissed_discussions_private_repo_announcement?
    end
  end
end
