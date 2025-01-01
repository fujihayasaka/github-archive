# typed: true
# frozen_string_literal: true

require "test_helper"

class InteractionLimits::SetInteractionLimitTest < GitHub::TestCase

  if GitHub.interaction_limits_enabled?
    fixtures do
      @staff = create(:staff_admin_user)
      @repo = create(:repository)
      @org = create(:business_organization)
      @org_repo = create(:repository, owner: @org)
      @user = @repo.owner
    end

    test "sets a limit for a repository for repo owner" do
      repo_interactions = RepositoryInteractionAbility.new(@repo)
      assert_equal :no_limit, repo_interactions.overall_active_limit

      inputs = {
        object: @repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @user,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @repo, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, repo_interactions.overall_active_limit
    end

    test "disables a limit for a repository for repo owner" do
      repo_interactions = RepositoryInteractionAbility.new(@repo)

      assert_equal :no_limit, repo_interactions.overall_active_limit
      assert repo_interactions.set_ability(:sockpuppet_disallowed, @user)
      assert_equal :sockpuppet_disallowed, repo_interactions.overall_active_limit

      inputs = {
        object: @repo,
        limit: :no_limit,
        actor: @user,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @repo, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :no_limit, repo_interactions.overall_active_limit
    end

    test "sets a limit for a repository for repo admin" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      repo_admin = create(:user)
      @org_repo.add_member(repo_admin, action: :admin)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: repo_admin,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_repo_interactions.overall_active_limit
    end

    test "sets a limit for a repository for repo maintainer" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      maintainer = create(:user)
      @org_repo.add_member(maintainer, action: :maintain)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: maintainer,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_repo_interactions.overall_active_limit
    end

    test "sets a limit for a repository for site admin" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @staff,
        staff_actor: true,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_repo_interactions.overall_active_limit
    end

    test "does not allow setting a limit for a repository for site admin where staff_actor is false" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @staff,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_equal "You are not authorized to set interaction limits.", result.error
      assert_equal Platform::Errors::Forbidden, result.platform_error
      assert_equal :no_limit, org_repo_interactions.overall_active_limit
    end

    test "does not allow setting a limit for a repository for unauthorized user" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: create(:user),
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_equal "You are not authorized to set interaction limits.", result.error
      assert_equal Platform::Errors::Forbidden, result.platform_error
      assert_equal :no_limit, org_repo_interactions.overall_active_limit
    end

    test "does not allow setting an invalid limit" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :marianne_von_edmund,
        duration: :one_day,
        actor: @org.admin,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_equal "You must specify a valid limit.", result.error
      assert_equal Platform::Errors::Unprocessable, result.platform_error
      assert_equal :no_limit, org_repo_interactions.overall_active_limit
    end

    test "does not allow setting an invalid duration" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      assert_equal :no_limit, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :sockpuppet_disallowed,
        duration: :dorte_the_horse,
        actor: @org.admin,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org_repo, result.object
      assert_equal "You must specify a valid duration.", result.error
      assert_equal Platform::Errors::Unprocessable, result.platform_error
      assert_equal :no_limit, org_repo_interactions.overall_active_limit
    end

    test "sets a limit for an organization for org admin" do
      org_interactions = RepositoryInteractionAbility.new(@org)
      assert_equal :no_limit, org_interactions.overall_active_limit

      inputs = {
        object: @org,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @org.admin,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_interactions.overall_active_limit
    end

    test "sets a limit for an organization for moderator" do
      org_interactions = RepositoryInteractionAbility.new(@org)

      moderator = create(:user)
      @org.add_member(moderator)
      moderation = Organization::Moderation.new(@org)
      moderation.add_moderator(moderator, actor: @org.admin)
      assert @org.moderator?(moderator)

      assert_equal :no_limit, org_interactions.overall_active_limit

      inputs = {
        object: @org,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: moderator,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_interactions.overall_active_limit
    end

    test "sets a limit for an organization for site admin" do
      org_interactions = RepositoryInteractionAbility.new(@org)

      assert_equal :no_limit, org_interactions.overall_active_limit

      inputs = {
        object: @org,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @staff,
        staff_actor: true,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @org, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, org_interactions.overall_active_limit
    end

    test "does not allow setting a limit for an organization for unauthorized user" do
      org_interactions = RepositoryInteractionAbility.new(@org)

      assert_equal :no_limit, org_interactions.overall_active_limit

      inputs = {
        object: @org,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: create(:user),
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org, result.object
      assert_equal "You are not authorized to set interaction limits.", result.error
      assert_equal Platform::Errors::Forbidden, result.platform_error
      assert_equal :no_limit, org_interactions.overall_active_limit
    end

    test "sets a limit for a user" do
      user_interactions = RepositoryInteractionAbility.new(@user)
      assert_equal :no_limit, user_interactions.overall_active_limit

      inputs = {
        object: @user,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @user,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @user, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, user_interactions.overall_active_limit
    end

    test "sets a limit for a user for site admin" do
      user_interactions = RepositoryInteractionAbility.new(@user)

      assert_equal :no_limit, user_interactions.overall_active_limit

      inputs = {
        object: @user,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: @staff,
        staff_actor: true,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      assert_predicate result, :success?
      assert_equal @user, result.object
      assert_nil result.error
      assert_nil result.platform_error
      assert_equal :sockpuppet_disallowed, user_interactions.overall_active_limit
    end

    test "does not allow setting a limit for a user for unauthorized user" do
      user_interactions = RepositoryInteractionAbility.new(@user)
      assert_equal :no_limit, user_interactions.overall_active_limit

      inputs = {
        object: @user,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: create(:user),
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @user, result.object
      assert_equal "You are not authorized to set interaction limits.", result.error
      assert_equal Platform::Errors::Forbidden, result.platform_error
      assert_equal :no_limit, user_interactions.overall_active_limit
    end

    test "does not allow setting limit for private repository" do
      repo = create(:private_repository)
      interactions = RepositoryInteractionAbility.new(repo)
      assert_equal :no_limit, interactions.overall_active_limit

      inputs = {
        object: repo,
        limit: :sockpuppet_disallowed,
        duration: :one_day,
        actor: repo.owner,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal repo, result.object
      assert_equal "Interaction limits cannot be set for private repositories.", result.error
      assert_equal Platform::Errors::Unprocessable, result.platform_error
      assert_equal :no_limit, interactions.overall_active_limit
    end

    test "does not allow setting limit for repository with org level limit" do
      org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)
      org_interactions = RepositoryInteractionAbility.new(@org)

      assert org_interactions.set_ability(:sockpuppet_disallowed, @org.admin)
      assert_equal :sockpuppet_disallowed, org_interactions.overall_active_limit
      assert_equal :sockpuppet_disallowed, org_repo_interactions.overall_active_limit

      inputs = {
        object: @org_repo,
        limit: :collaborators_only,
        duration: :one_day,
        actor: @org.admin,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @org_repo, result.object
      error = "Cannot set an interaction limit for this repository because there is an active limit at the organization level."
      assert_equal error, result.error
      assert_equal Platform::Errors::Unprocessable, result.platform_error
      assert_equal :sockpuppet_disallowed, org_interactions.overall_active_limit
      assert_equal :sockpuppet_disallowed, org_repo_interactions.overall_active_limit
    end

    test "does not allow setting limit for repository with user level limit" do
      user_interactions = RepositoryInteractionAbility.new(@user)
      repo_interactions = RepositoryInteractionAbility.new(@repo)

      assert user_interactions.set_ability(:sockpuppet_disallowed, @user)
      assert_equal :sockpuppet_disallowed, user_interactions.overall_active_limit
      assert_equal :sockpuppet_disallowed, repo_interactions.overall_active_limit

      inputs = {
        object: @repo,
        limit: :collaborators_only,
        duration: :one_day,
        actor: @user,
      }

      result = InteractionLimits::SetInteractionLimit.call(inputs)
      refute_predicate result, :success?
      assert_equal @repo, result.object
      error = "Cannot set an interaction limit for this repository because there is an active limit at the user level."
      assert_equal error, result.error
      assert_equal Platform::Errors::Unprocessable, result.platform_error
      assert_equal :sockpuppet_disallowed, user_interactions.overall_active_limit
      assert_equal :sockpuppet_disallowed, repo_interactions.overall_active_limit
    end
  end
end
