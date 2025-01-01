# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.interaction_limits_enabled?
  class RepositoryInteractionBlockingTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @staff = create(:staff_admin_user)
      @user = create(:user)
      @repo = create(:repository, owner: @user)
      @rando = create(:user)

      @org = create(:organization, admin: @user)
      @org_repo = create(:repository, owner: @org)
      org_interactions = RepositoryInteractionAbility.new(@org)
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
    end

    context ".sockpuppet_disallowed_enabled?" do
      test "true for repo with limit set" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@repo)
      end

      test "true for org with limit set" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)
      end

      test "true for user with limit set" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@user)
      end
    end

    context ".contributors_only_enabled?" do
      test "true for repo with limit set" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        repo_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@repo)
      end

      test "true for org with limit set" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@org)
      end

      test "true for user with limit set" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@user)
      end
    end

    context ".collaborators_only_enabled?" do
      test "true for repo with limit set" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        repo_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@repo)
      end

      test "true for org with limit set" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@org)
      end

      test "true for user with limit set" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@user)
      end
    end

    context ".async_interaction_allowed?" do
      test "returns true if no limit is enabled" do
        assert RepositoryInteractionAbility.async_interaction_allowed?(
          repository: @org_repo,
          user: @rando,
        ).sync
      end

      test "returns true if exempt from local limit" do
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
        assert org_repo_interactions.set_ability(:collaborators_only, @user)

        assert RepositoryInteractionAbility.async_interaction_allowed?(
          repository: @org_repo,
          user: @user,
        ).sync
      end

      test "returns true if exempt from global limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        assert org_interactions.set_ability(:collaborators_only, @user)

        assert RepositoryInteractionAbility.async_interaction_allowed?(
          repository: @org_repo,
          user: @user,
        ).sync
      end

      test "returns false if not exempt from limit" do
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
        assert org_repo_interactions.set_ability(:collaborators_only, @user)

        refute RepositoryInteractionAbility.async_interaction_allowed?(
          repository: @org_repo,
          user: @rando,
        ).sync
      end

      test "returns false if repository is nil" do
        refute RepositoryInteractionAbility.async_interaction_allowed?(
          repository: nil,
          user: @user,
        ).sync
      end

      test "returns false if user is nil" do
        refute RepositoryInteractionAbility.async_interaction_allowed?(
          repository: @org_repo,
          user: nil,
        ).sync
      end
    end

    context ".restricted_by_limit?" do
      test "false if the limit is not enabled" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        user = create(:user)

        refute repo_interactions.collaborators_only_enabled?
        refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
        refute RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @repo, user)
      end

      test "raises if limit name is not valid" do
        assert_raises ArgumentError do
          RepositoryInteractionAbility.restricted_by_limit?(:peppermint_sombra, @repo, @user)
        end
      end

      context "per-repo limits" do
        test "false if the limit is enabled but the user is exempt" do
          repo_interactions = RepositoryInteractionAbility.new(@repo)
          repo_interactions.set_ability(:collaborators_only, @user)

          user = create(:user)

          @repo.add_member(user)

          assert repo_interactions.collaborators_only_enabled?
          assert RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
          refute RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @repo, user)
        end

        test "true if limit is enabled and user is not exempt" do
          repo_interactions = RepositoryInteractionAbility.new(@repo)
          repo_interactions.set_ability(:collaborators_only, @user)

          user = create(:user)

          assert repo_interactions.collaborators_only_enabled?
          refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
          assert RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @repo, user)
        end

        test "true if the user is blocked" do
          repo_interactions = RepositoryInteractionAbility.new(@repo)
          user = create(:user)
          blocked_user = create(:user)
          @repo.owner.block(blocked_user)

          refute RepositoryInteractionAbility.blocked?(@repo, user)
          assert RepositoryInteractionAbility.blocked?(@repo, blocked_user)
        end
      end

      context "org-wide limits" do
        test "false if repo is private" do
          org_interactions = RepositoryInteractionAbility.new(@org)
          private_repo = create(:private_repository, owner: @org)
          user = create(:user)
          private_repo.add_member(user, action: :read)

          org_interactions.set_ability(:sockpuppet_disallowed, @user)
          assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)

          assert RepositoryInteractionAbility.restricted_by_limit?(:sockpuppet_disallowed, @org_repo, user)
          assert private_repo.private?
          refute RepositoryInteractionAbility.restricted_by_limit?(:sockpuppet_disallowed, private_repo, user)
        end

        test "false if limit is enabled at org level and user is member of org" do
          org_interactions = RepositoryInteractionAbility.new(@org)
          org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
          org_interactions.set_ability(:collaborators_only, @user)

          org_member = create(:user)
          @org.add_member(org_member)

          assert org_interactions.collaborators_only_enabled?
          refute org_repo_interactions.collaborators_only_enabled?
          assert RepositoryInteractionAbility.user_exempt?(:collaborators_only, @org_repo, org_member)
          refute RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @org_repo, org_member)
        end

        test "false if limit is enabled at org level and user is member of org via a team" do
          org_interactions = RepositoryInteractionAbility.new(@org)
          org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
          org_interactions.set_ability(:collaborators_only, @user)

          team_member = create(:user)
          team = create(:team, organization: @org)
          team.add_member(team_member)

          assert org_interactions.collaborators_only_enabled?
          refute org_repo_interactions.collaborators_only_enabled?
          assert RepositoryInteractionAbility.user_exempt?(:collaborators_only, @org_repo, team_member)
          refute RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @org_repo, team_member)
        end

        test "true if limit is enabled at org level and user is billing manager of org" do
          org_interactions = RepositoryInteractionAbility.new(@org)
          org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
          org_interactions.set_ability(:collaborators_only, @user)

          billing_mgr = create(:user)
          @org.billing.add_manager(billing_mgr, actor: @user)

          assert org_interactions.collaborators_only_enabled?
          refute org_repo_interactions.collaborators_only_enabled?
          refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @org_repo, billing_mgr)
          assert RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @org_repo, billing_mgr)
        end

        test "true if limit is enabled at org level and user is not exempt" do
          org_interactions = RepositoryInteractionAbility.new(@org)
          org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
          org_interactions.set_ability(:collaborators_only, @user)

          non_org_member = create(:user)

          assert org_interactions.collaborators_only_enabled?
          refute org_repo_interactions.collaborators_only_enabled?
          refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @org_repo, non_org_member)
          assert RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @org_repo, non_org_member)
        end
      end

      context "user-wide limits" do
        test "true if limit is enabled at user level and user is not exempt" do
          repo_interactions = RepositoryInteractionAbility.new(@repo)
          user_interactions = RepositoryInteractionAbility.new(@user)
          user_interactions.set_ability(:collaborators_only, @user)

          user = create(:user)

          assert user_interactions.collaborators_only_enabled?
          refute repo_interactions.collaborators_only_enabled?
          refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
          assert RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, @repo, user)
        end
      end
    end

    context "#async_local_active_limit" do
      test "returns the correct limit that is enabled" do
        ability = RepositoryInteractionAbility.new(@repo)

        refute_predicate ability, :sockpuppet_disallowed_enabled?
        refute_predicate ability, :contributors_only_enabled?
        refute_predicate ability, :collaborators_only_enabled?
        assert_equal :no_limit, ability.async_local_active_limit.sync

        ability.set_ability(:sockpuppet_disallowed, @user)
        assert_equal :sockpuppet_disallowed, ability.async_local_active_limit.sync

        ability.set_ability(:contributors_only, @user)
        assert_equal :contributors_only, ability.async_local_active_limit.sync

        ability.set_ability(:collaborators_only, @user)
        assert_equal :collaborators_only, ability.async_local_active_limit.sync
      end
    end

    context ".user_exempt?" do
      context "for sockpuppet_disallowed limit" do
        test "true if user wasn't created recently" do
          user = create(:user, created_at: 2.days.ago)

          assert RepositoryInteractionAbility.user_exempt?(:sockpuppet_disallowed, @repo, user)
        end

        test "true if user was created recently but is a contributor" do
          user = create(:user)

          create(:commit_contribution, user: user, repository: @repo)

          assert @repo.contributor?(user)
          assert RepositoryInteractionAbility.user_exempt?(:sockpuppet_disallowed, @repo, user)
        end

        test "true if user was created recently but is a collaborator" do
          user = create(:user)

          @repo.add_member(user)

          assert @repo.member_ids.include?(user.id)
          assert RepositoryInteractionAbility.user_exempt?(:sockpuppet_disallowed, @repo, user)
        end

        test "true if user is a bot" do
          integration = create(:integration)
          bot = integration.bot

          refute @repo.contributor?(bot)
          assert RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, bot)
        end

        test "false if user was created recently and is not a contributor or collaborator" do
          user = create(:user)

          refute @repo.contributor?(user)
          refute @repo.member_ids.include?(user.id)
          refute RepositoryInteractionAbility.user_exempt?(:sockpuppet_disallowed, @repo, user)
        end
      end

      context "for contributors_only limit" do
        test "true if user is a contributor" do
          user = create(:user)

          create(:commit_contribution, user: user, repository: @repo)

          assert @repo.contributor?(user)
          assert RepositoryInteractionAbility.user_exempt?(:contributors_only, @repo, user)
        end

        test "true if user is not a contributor but is a collaborator" do
          user = create(:user)

          @repo.add_member(user)

          refute @repo.contributor?(user)
          assert @repo.member_ids.include?(user.id)
          assert RepositoryInteractionAbility.user_exempt?(:contributors_only, @repo, user)
        end

        test "false if user is not a contributor or collaborator" do
          user = create(:user)

          refute @repo.contributor?(user)
          refute @repo.member_ids.include?(user.id)
          refute RepositoryInteractionAbility.user_exempt?(:contributors_only, @repo, user)
        end
      end

      context "for collaborators_only limit" do
        test "true if user is a collaborator" do
          user = create(:user)

          @repo.add_member(user)

          assert @repo.member_ids.include?(user.id)
          assert RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
        end

        test "false if user is a contributor but not a collaborator" do
          user = create(:user)

          create(:commit_contribution, user: user, repository: @repo)

          assert @repo.contributor?(user)

          refute @repo.member_ids.include?(user.id)
          refute RepositoryInteractionAbility.user_exempt?(:collaborators_only, @repo, user)
        end
      end

      test "raises if limit name is not valid" do
        assert_raises ArgumentError do
          RepositoryInteractionAbility.user_exempt?(:acid_burn, @repo, @user)
        end
      end
    end

    context ".disable_active_local_limit_for" do
      test "disables any active interaction limits for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@repo)

        RepositoryInteractionAbility.disable_active_local_limit_for(@repo)
        refute RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@repo)

        repo_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@repo)

        RepositoryInteractionAbility.disable_active_local_limit_for(@repo)
        refute RepositoryInteractionAbility.contributors_only_enabled?(@repo)

        repo_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@repo)

        RepositoryInteractionAbility.disable_active_local_limit_for(@repo)
        refute RepositoryInteractionAbility.collaborators_only_enabled?(@repo)
      end

      test "disables any active interaction limits for an org" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)

        RepositoryInteractionAbility.disable_active_local_limit_for(@org)
        refute RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)

        org_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@org)

        RepositoryInteractionAbility.disable_active_local_limit_for(@org)
        refute RepositoryInteractionAbility.contributors_only_enabled?(@org)

        org_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@org)

        RepositoryInteractionAbility.disable_active_local_limit_for(@org)
        refute RepositoryInteractionAbility.collaborators_only_enabled?(@org)
      end

      test "disables any active interaction limits for a user" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@user)

        RepositoryInteractionAbility.disable_active_local_limit_for(@user)
        refute RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@user)

        user_interactions.set_ability(:contributors_only, @user)
        assert RepositoryInteractionAbility.contributors_only_enabled?(@user)

        RepositoryInteractionAbility.disable_active_local_limit_for(@user)
        refute RepositoryInteractionAbility.contributors_only_enabled?(@user)

        user_interactions.set_ability(:collaborators_only, @user)
        assert RepositoryInteractionAbility.collaborators_only_enabled?(@user)

        RepositoryInteractionAbility.disable_active_local_limit_for(@user)
        refute RepositoryInteractionAbility.collaborators_only_enabled?(@user)
      end

      test "instruments when ban is disabled for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.disable_sockpuppet_disallowed")

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)

        RepositoryInteractionAbility.disable_active_local_limit_for(@repo, @user)

        expected_payload = {
          repo: @repo.nwo, repo_id: @repo.id, public_repo: @repo.public?, actor: @user.login, actor_id: @user.id
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments when ban is disabled for an org" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        events = subscribe("org.config.enable_sockpuppet_disallowed")

        assert org_interactions.set_ability(:sockpuppet_disallowed, @user)

        RepositoryInteractionAbility.disable_active_local_limit_for(@org, @user)

        expected_payload = {
          org: @org.login,
          org_id: @org.id,
          actor: @user.login,
          actor_id: @user.id,
          duration: 0,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments when ban is disabled for a user" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        events = subscribe("user.enable_sockpuppet_disallowed")

        assert user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert user_interactions.set_ability(:no_limit, @user)

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          actor: @user.login,
          actor_id: @user.id,
          duration: 0,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments for repo with guarded staff actor" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.disable_sockpuppet_disallowed")

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @staff)

        RepositoryInteractionAbility.disable_active_local_limit_for(@repo, @staff, staff_actor: true)

        expected_payload = {
          repo: @repo.nwo,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments for org with guarded staff actor" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        events = subscribe("org.config.disable_sockpuppet_disallowed")

        assert org_interactions.set_ability(:sockpuppet_disallowed, @staff)

        RepositoryInteractionAbility.disable_active_local_limit_for(@org, @staff, staff_actor: true)

        expected_payload = {
          org: @org.login,
          org_id: @org.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments for user with guarded staff actor" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        events = subscribe("user.disable_sockpuppet_disallowed")

        assert user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert user_interactions.set_ability(:no_limit, @staff, staff_actor: true)

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    context ".has_active_limits?" do
      test "true if repo has an interaction limit enabled" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@repo)

        assert RepositoryInteractionAbility.has_active_limits?(@repo)
      end

      test "true for repo if an org has an interaction limit enabled" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)
        refute RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org_repo)

        assert RepositoryInteractionAbility.has_active_limits?(@org_repo)
      end

      test "true for repo if a user has an interaction limit enabled" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@user)
        refute RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@repo)

        assert RepositoryInteractionAbility.has_active_limits?(@repo)
      end

      test "true for org that has an interaction limit enabled" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)

        assert RepositoryInteractionAbility.has_active_limits?(@org)
      end

      test "true user org that has an interaction limit enabled" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@user)

        assert RepositoryInteractionAbility.has_active_limits?(@user)
      end

      test "false if repo is private" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        private_repo = create(:private_repository, owner: @org)

        org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert RepositoryInteractionAbility.sockpuppet_disallowed_enabled?(@org)

        assert RepositoryInteractionAbility.has_active_limits?(@org_repo)
        assert private_repo.private?
        refute RepositoryInteractionAbility.has_active_limits?(private_repo)
      end
    end

    context "#sockpuppet_disallowed_enabled?" do
      test "true for a repo with a limit" do
        @repo.enable_repo_interaction_limit(restriction: :sockpuppet_disallowed, expires_at: 1.day.from_now)

        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.sockpuppet_disallowed_enabled?
      end

      test "false for a repo without a limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        refute repo_interactions.sockpuppet_disallowed_enabled?
      end

      test "true for an org with a limit" do
        @org.enable_repo_interaction_limit(restriction: :sockpuppet_disallowed, expires_at: 1.day.from_now)

        org_interactions = RepositoryInteractionAbility.new(@org)
        assert org_interactions.sockpuppet_disallowed_enabled?
      end

      test "true for a user with a limit" do
        @user.enable_repo_interaction_limit(restriction: :sockpuppet_disallowed, expires_at: 1.day.from_now)

        user_interactions = RepositoryInteractionAbility.new(@user)
        assert user_interactions.sockpuppet_disallowed_enabled?
      end

      test "false for an org without a limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        refute org_interactions.sockpuppet_disallowed_enabled?
      end
    end

    context "#async_local_active_limit_expiry" do
      [
        [:one_day, 1.day],
        [:three_days, 3.days],
        [:one_week, 1.week],
        [:one_month, 1.month],
        [:six_months, 6.months],
      ].each do |duration, date_time_value|
        test "sets the proper expiration for #{duration}" do
          org_interactions = RepositoryInteractionAbility.new(@org)

          freeze_time do
            org_interactions.set_ability(:sockpuppet_disallowed, @staff, duration)
            expires_at = org_interactions.local_active_limit_expiry

            assert_equal date_time_value.from_now.to_i, expires_at.to_i
          end
        end
      end

      test "is nil if limit is not enabled" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        refute repo_interactions.sockpuppet_disallowed_enabled?

        assert_nil repo_interactions.async_local_active_limit_expiry.sync
      end
    end

    context "#contributors_only_enabled?" do
      test "true for a repo with a limit" do
        @repo.enable_repo_interaction_limit(restriction: :contributors_only, expires_at: 1.day.from_now)

        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.contributors_only_enabled?
      end

      test "false for a repo without a limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        refute repo_interactions.contributors_only_enabled?
      end

      test "true for an org with a limit" do
        @org.enable_repo_interaction_limit(restriction: :contributors_only, expires_at: 1.day.from_now)

        org_interactions = RepositoryInteractionAbility.new(@org)
        assert org_interactions.contributors_only_enabled?
      end

      test "true for a user with a limit" do
        @user.enable_repo_interaction_limit(restriction: :contributors_only, expires_at: 1.day.from_now)

        user_interactions = RepositoryInteractionAbility.new(@user)
        assert user_interactions.contributors_only_enabled?
      end

      test "false for an org without a limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        refute org_interactions.contributors_only_enabled?
      end
    end

    context "#collaborators_only_enabled?" do
      test "true for a repo with a limit" do
        @repo.enable_repo_interaction_limit(restriction: :collaborators_only, expires_at: 1.day.from_now)

        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.collaborators_only_enabled?
      end

      test "false for a repo without a limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        refute repo_interactions.collaborators_only_enabled?
      end

      test "true for an org with a limit" do
        @org.enable_repo_interaction_limit(restriction: :collaborators_only, expires_at: 1.day.from_now)

        org_interactions = RepositoryInteractionAbility.new(@org)
        assert org_interactions.collaborators_only_enabled?
      end

      test "true for an user with a limit" do
        @user.enable_repo_interaction_limit(restriction: :collaborators_only, expires_at: 1.day.from_now)

        user_interactions = RepositoryInteractionAbility.new(@user)
        assert user_interactions.collaborators_only_enabled?
      end

      test "false for an org without a limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        refute org_interactions.collaborators_only_enabled?
      end
    end

    context "#set_ability" do
      test "sets a limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        refute_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?

        assert repo_interactions.set_ability(:no_limit, @user)
        refute_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?
      end

      test "sets a limit for an org" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        refute_predicate org_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate org_interactions, :contributors_only_enabled?
        refute_predicate org_interactions, :collaborators_only_enabled?

        assert org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate org_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate org_interactions, :contributors_only_enabled?
        refute_predicate org_interactions, :collaborators_only_enabled?

        assert org_interactions.set_ability(:no_limit, @user)
        refute_predicate org_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate org_interactions, :contributors_only_enabled?
        refute_predicate org_interactions, :collaborators_only_enabled?
      end

      test "sets a limit for a user" do
        user_interactions = RepositoryInteractionAbility.new(@user)

        refute_predicate user_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate user_interactions, :contributors_only_enabled?
        refute_predicate user_interactions, :collaborators_only_enabled?

        assert user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate user_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate user_interactions, :contributors_only_enabled?
        refute_predicate user_interactions, :collaborators_only_enabled?

        assert user_interactions.set_ability(:no_limit, @user)
        refute_predicate user_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate user_interactions, :contributors_only_enabled?
        refute_predicate user_interactions, :collaborators_only_enabled?
      end

      test "does nothing if limit is already enabled" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        refute_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate repo_interactions, :contributors_only_enabled?
        refute_predicate repo_interactions, :collaborators_only_enabled?
      end

      test "allows updating the current limit's expiry" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        Timecop.freeze do
          old_time = 1.day.from_now.to_i
          new_time = 1.week.from_now.to_i

          assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
          assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?
          assert_equal old_time, repo_interactions.local_active_limit_expiry.to_i


          assert repo_interactions.set_ability(:sockpuppet_disallowed, @user, :one_week)
          assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?
          assert_equal new_time, repo_interactions.local_active_limit_expiry.to_i
        end
      end

      test "does not set limit for a repo if an org level limit is enabled" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        assert org_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_interactions, :collaborators_only_enabled?

        refute org_repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        refute_predicate org_repo_interactions, :sockpuppet_disallowed_enabled?
      end

      test "does not set limit for a repo if an user level limit is enabled" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert user_interactions.set_ability(:collaborators_only, @user)
        assert_predicate user_interactions, :collaborators_only_enabled?

        refute repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        refute_predicate repo_interactions, :sockpuppet_disallowed_enabled?
      end

      test "disables repo level interaction limits when setting org level limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        other_repo = create(:repository, owner: @org)
        other_repo_interactions = RepositoryInteractionAbility.new(other_repo)

        other_repo_interactions.set_ability(:contributors_only, @user)
        org_repo_interactions.set_ability(:sockpuppet_disallowed, @user)

        assert other_repo_interactions.contributors_only_enabled?
        assert org_repo_interactions.sockpuppet_disallowed_enabled?

        perform_enqueued_jobs(only: [DisableRepositoryInteractionLimitsJob]) do
          org_interactions.set_ability(:collaborators_only, @user)
        end

        refute org_repo_interactions.sockpuppet_disallowed_enabled?
        refute other_repo_interactions.contributors_only_enabled?
        assert org_interactions.collaborators_only_enabled?
      end

      test "disables repo level interaction limits when setting user level limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        user_interactions = RepositoryInteractionAbility.new(@user)
        other_repo = create(:repository, owner: @user)
        other_repo_interactions = RepositoryInteractionAbility.new(other_repo)

        other_repo_interactions.set_ability(:contributors_only, @user)
        repo_interactions.set_ability(:sockpuppet_disallowed, @user)

        assert other_repo_interactions.contributors_only_enabled?
        assert repo_interactions.sockpuppet_disallowed_enabled?

        perform_enqueued_jobs(only: [DisableRepositoryInteractionLimitsJob]) do
          user_interactions.set_ability(:collaborators_only, @user)
        end

        refute repo_interactions.sockpuppet_disallowed_enabled?
        refute other_repo_interactions.contributors_only_enabled?
        assert user_interactions.collaborators_only_enabled?
      end

      test "increments stats for enabling a user interaction limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        user_interactions.set_ability(:sockpuppet_disallowed, @user)

        assert user_interactions.sockpuppet_disallowed_enabled?
        assert_equal 1, GitHub.dogstats.increments("sockpuppet_disallowed.enable", tags: ["type:user"]).count
      end

      test "instruments to audit log when ban is enabled for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.enable_sockpuppet_disallowed")
        repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        expected_payload = {
          repo: @repo.nwo,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          actor: @user.login,
          actor_id: @user.id,
          duration: 0,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments hydro event when ban is enabled for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)

        expected_message = {
          target_type: "REPOSITORY",
          target_id: @repo.id,
          limit: "SOCKPUPPET_DISALLOWED",
          actor: Hydro::EntitySerializer.user(@user),
          staff_actor: false,
          duration_value: 1,
          duration_unit: "DAY",
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitEnable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitEnable")
      end

      test "instruments hydro event when ban is enabled for a user" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        assert user_interactions.set_ability(:sockpuppet_disallowed, @user)

        expected_message = {
          target_type: "USER",
          target_id: @user.id,
          limit: "SOCKPUPPET_DISALLOWED",
          actor: Hydro::EntitySerializer.user(@user),
          staff_actor: false,
          duration_value: 1,
          duration_unit: "DAY",
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitEnable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitEnable")
      end

      test "instruments to audit log with guarded staff actor" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.enable_sockpuppet_disallowed")
        repo_interactions.set_ability(:sockpuppet_disallowed, @staff, staff_actor: true)
        expected_payload = {
          repo: @repo.nwo,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
          duration: 0,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments hydro event when ban is enabled for a repo with staff actor" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.set_ability(:sockpuppet_disallowed, @staff, staff_actor: true)

        expected_message = {
          target_type: "REPOSITORY",
          target_id: @repo.id,
          limit: "SOCKPUPPET_DISALLOWED",
          actor: Hydro::EntitySerializer.user(@staff),
          staff_actor: true,
          duration_value: 1,
          duration_unit: "DAY",
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitEnable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitEnable")
      end

      test "instruments to audit log when ban is disabled for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.disable_sockpuppet_disallowed")

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert repo_interactions.set_ability(:no_limit, @user)

        expected_payload = {
          repo: @repo.nwo,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          actor: @user.login,
          actor_id: @user.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "does not instrument disable to audit log if expiry is being updated" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        events = subscribe("repo.config.disable_sockpuppet_disallowed")

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user, :one_week)

        assert_empty events
      end

      test "instruments hydro event when ban is disabled for a repo" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert repo_interactions.set_ability(:no_limit, @user)

        expected_message = {
          target_type: "REPOSITORY",
          target_id: @repo.id,
          limit: "SOCKPUPPET_DISALLOWED",
          staff_actor: false,
          actor: Hydro::EntitySerializer.user(@user),
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitDisable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitDisable")
      end

      test "instruments to audit log when ban is disabled for an org" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        events = subscribe("org.config.enable_sockpuppet_disallowed")

        assert org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert org_interactions.set_ability(:no_limit, @user)

        expected_payload = {
          org: @org.login,
          org_id: @org.id,
          actor: @user.login,
          actor_id: @user.id,
          duration: 0,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments hydro event when ban is disabled for an org" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        assert org_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert org_interactions.set_ability(:no_limit, @user)

        expected_message = {
          target_type: "ORGANIZATION",
          target_id: @org.id,
          limit: "SOCKPUPPET_DISALLOWED",
          staff_actor: false,
          actor: Hydro::EntitySerializer.user(@user),
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitDisable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitDisable")
      end

      test "instruments hydro event when ban is disabled for a user" do
        user_interactions = RepositoryInteractionAbility.new(@user)

        assert user_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert user_interactions.set_ability(:no_limit, @user)

        expected_message = {
          target_type: "USER",
          target_id: @user.id,
          limit: "SOCKPUPPET_DISALLOWED",
          staff_actor: false,
          actor: Hydro::EntitySerializer.user(@user),
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitDisable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitDisable")
      end

      test "instruments disabling to audit log for repo with guarded staff actor" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        events = subscribe("repo.config.disable_sockpuppet_disallowed")

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @staff)
        assert repo_interactions.set_ability(:no_limit, @staff, staff_actor: true)

        expected_payload = {
          repo: @repo.nwo,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments hydro event when ban is disabled for a repo with staff actor" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @staff)
        assert repo_interactions.set_ability(:no_limit, @staff, staff_actor: true)

        expected_message = {
          target_type: "REPOSITORY",
          target_id: @repo.id,
          limit: "SOCKPUPPET_DISALLOWED",
          staff_actor: true,
          actor: Hydro::EntitySerializer.user(@staff),
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitDisable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitDisable")
      end

      test "instruments disabling to audit log for org with guarded staff actor" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        events = subscribe("org.config.disable_sockpuppet_disallowed")

        assert org_interactions.set_ability(:sockpuppet_disallowed, @staff)
        assert org_interactions.set_ability(:no_limit, @staff, staff_actor: true)

        expected_payload = {
          org: @org.login,
          org_id: @org.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
        }
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments hydro event when ban is disabled for a org with staff actor" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        assert org_interactions.set_ability(:sockpuppet_disallowed, @staff)
        assert org_interactions.set_ability(:no_limit, @staff, staff_actor: true)

        expected_message = {
          target_type: "ORGANIZATION",
          target_id: @org.id,
          limit: "SOCKPUPPET_DISALLOWED",
          staff_actor: true,
          actor: Hydro::EntitySerializer.user(@staff),
        }

        assert_hydro_messages(count: 1, schema: "github.interaction_ability.v0.InteractionLimitDisable")
        assert_hydro_published(expected_message, schema: "github.interaction_ability.v0.InteractionLimitDisable")
      end
    end

    context "#async_overall_active_limit" do
      test "returns the limit for repository configured limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?

        assert_equal :sockpuppet_disallowed, repo_interactions.async_overall_active_limit.sync
      end

      test "returns the limit for an organization configured limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        assert org_repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate org_repo_interactions, :sockpuppet_disallowed_enabled?

        assert org_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_interactions, :collaborators_only_enabled?

        assert_equal :collaborators_only, org_repo_interactions.async_overall_active_limit.sync
      end

      test "returns the limit for a user configured limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?

        assert user_interactions.set_ability(:collaborators_only, @user)
        assert_predicate user_interactions, :collaborators_only_enabled?

        assert_equal :collaborators_only, repo_interactions.async_overall_active_limit.sync
      end
    end

    context "#async_active_limit_origin" do
      test "returns repository for repo configured limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
        assert_predicate repo_interactions, :sockpuppet_disallowed_enabled?

        assert_equal :repository, repo_interactions.async_active_limit_origin.sync
      end

      test "returns organization for repo with org configured limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        assert org_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_interactions, :collaborators_only_enabled?

        assert_equal :organization, org_repo_interactions.async_active_limit_origin.sync
      end

      test "returns user for repo with user configured limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert user_interactions.set_ability(:collaborators_only, @user)
        assert_predicate user_interactions, :collaborators_only_enabled?

        assert_equal :user, repo_interactions.async_active_limit_origin.sync
      end

      test "returns organization for org with org configured limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        assert org_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_interactions, :collaborators_only_enabled?

        assert_equal :organization, org_interactions.async_active_limit_origin.sync
      end

      test "returns user for user with user configured limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)

        assert user_interactions.set_ability(:collaborators_only, @user)
        assert_predicate user_interactions, :collaborators_only_enabled?

        assert_equal :user, user_interactions.async_active_limit_origin.sync
      end
    end

    context "#async_has_overall_limit?" do
      test "true for repo with active org limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        assert org_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_interactions, :collaborators_only_enabled?

        assert org_repo_interactions.async_has_overall_limit?.sync
      end

      test "true for repo with active user limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)
        user_interactions = RepositoryInteractionAbility.new(@user)

        assert user_interactions.set_ability(:collaborators_only, @user)
        assert_predicate user_interactions, :collaborators_only_enabled?

        assert repo_interactions.async_has_overall_limit?.sync
      end

      test "false for user owned repo without active user limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        assert repo_interactions.set_ability(:collaborators_only, @user)
        assert_predicate repo_interactions, :collaborators_only_enabled?

        refute repo_interactions.async_has_overall_limit?.sync
      end

      test "false for repo without active org limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        refute_predicate org_interactions, :sockpuppet_disallowed_enabled?
        refute_predicate org_interactions, :contributors_only_enabled?
        refute_predicate org_interactions, :collaborators_only_enabled?

        assert org_repo_interactions.set_ability(:collaborators_only, @user)
        assert_predicate org_repo_interactions, :collaborators_only_enabled?

        refute org_repo_interactions.async_has_overall_limit?.sync
      end
    end

    context "#async_overall_active_limit_expiry" do
      test "returns expiry for repo level limit" do
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        Timecop.freeze do
          assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)

          assert repo_interactions.sockpuppet_disallowed_enabled?
          expires_at = DateTime.parse(1.day.from_now.to_s)
          assert_equal expires_at.to_i, repo_interactions.async_overall_active_limit_expiry.sync.to_i
        end
      end

      test "return expiry for org level limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)

        Timecop.freeze do
          assert org_interactions.set_ability(:sockpuppet_disallowed, @user)

          assert org_interactions.sockpuppet_disallowed_enabled?
          expires_at = DateTime.parse(1.day.from_now.to_s)
          assert_equal expires_at.to_i, org_interactions.async_overall_active_limit_expiry.sync.to_i
        end
      end

      test "return expiry for user level limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)

        Timecop.freeze do
          assert user_interactions.set_ability(:sockpuppet_disallowed, @user)

          assert user_interactions.sockpuppet_disallowed_enabled?
          expires_at = DateTime.parse(1.day.from_now.to_s)
          assert_equal expires_at.to_i, user_interactions.async_overall_active_limit_expiry.sync.to_i
        end
      end

      test "returns expiry for repo with org level limit" do
        org_interactions = RepositoryInteractionAbility.new(@org)
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        Timecop.freeze do
          assert org_interactions.set_ability(:sockpuppet_disallowed, @user)

          assert org_interactions.sockpuppet_disallowed_enabled?
          expires_at = DateTime.parse(1.day.from_now.to_s)
          assert_equal expires_at.to_i, org_repo_interactions.async_overall_active_limit_expiry.sync.to_i
        end
      end

      test "returns expiry for repo with user level limit" do
        user_interactions = RepositoryInteractionAbility.new(@user)
        repo_interactions = RepositoryInteractionAbility.new(@repo)

        Timecop.freeze do
          assert user_interactions.set_ability(:sockpuppet_disallowed, @user)

          assert user_interactions.sockpuppet_disallowed_enabled?
          expires_at = DateTime.parse(1.day.from_now.to_s)
          assert_equal expires_at.to_i, repo_interactions.async_overall_active_limit_expiry.sync.to_i
        end
      end

      test "returns nil if no limit is enabled" do
        org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

        assert_nil org_repo_interactions.async_overall_active_limit_expiry.sync
      end
    end
  end
end
