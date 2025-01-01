# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProfilesDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @viewer = create(:user)
    email = create(:user_email, :verified, user: @user)

    # This repo is stored as a separate instance variable so we can modify
    # it but allows `fixtures` to roll it back. We do NOT get the same behavior
    # from the repositories created via `create_list` as the model instances
    # are not top-level instance variables. Note that the instance stored in
    # the array will also become outdated and not be automatically reloaded.
    @acv_repos = create_list(:repository, 8)
    @acv_repo = @acv_repos[0]

    acv_contributions = @acv_repos.map do |repo|
      create(:acv_contributor, repository: repo, contributor_email: email)
    end
    @acv_contribution = acv_contributions[0]
    @another_acv_contribution = acv_contributions[1]
  end

  context "#starred_repos_count" do
    test "returns the number of repositories the user has starred" do
      @user.star(create(:repository))

      assert_equal 1, @user.starred_repos_count
    end

    test "returns the number of repositories the user has starred and has access to" do
      # create starred repository without access
      repository = create(:private_repository)
      repository.add_member(@user)
      @user.star(repository)

      count_before = @user.starred_repos_count
      repository.remove_member(@user)

      @user.reload
      assert_equal (count_before - 1), @user.starred_repos_count
    end
  end

  context "#can_have_acv_badge?" do
    test "returns true if user has contributions" do
      create(:user_metadata, user: @user, has_acv_badge: true)

      assert_equal true, @user.can_have_acv_badge?
    end

    test "returns false if user does not have contributions" do
      rando = create(:user)
      create(:user_metadata, user: @user, has_acv_badge: true)

      assert_equal false, rando.can_have_acv_badge?
    end

    test "returns false for the ghost user even if it has contributions attributed" do
      ghost = User.ghost
      create(:user_metadata, user: ghost, has_acv_badge: true)

      # Add ALL THE EMAILS to prove it will NEVER return true
      # Primary (though unverified) email: ghost@github.com
      create(:acv_contributor, repository: @acv_repo, contributor_email: ghost.emails.first)
      # Modern stealh email: 123+ghost@users.noreply.github.com
      create(:acv_contributor, repository: @acv_repo, contributor_email: ghost.anonymous_user_email)
      # Modern stealth email but with username hardcoded: 123+username@users.noreply.github.com
      modern_email = "#{ghost.id}+username@#{GitHub.stealth_email_host_name}"
      create(:acv_contributor, repository: @acv_repo, contributor_email: modern_email)
      # Legacy stealth email: ghost@users.noreply.github.com
      legacy_email = StealthEmail.new(ghost).legacy_email
      create(:acv_contributor, repository: @acv_repo, contributor_email: legacy_email)

      assert_equal false, ghost.can_have_acv_badge?
    end
  end

  context "#all_acv_repository_ids" do
    test "returns ids of all ACV repositories the user contributed to" do
      assert_same_elements(@acv_repos.pluck(:id), @user.all_acv_repository_ids)
    end

    test "returns unique ids" do
      # Create another contribution record for the same repository but with an
      # alternative email address
      create(:acv_contributor, repository: @acv_repo, contributor_email: @user.anonymous_user_email)

      assert_same_elements(@acv_repos.pluck(:id), @user.all_acv_repository_ids)
    end

    # This represents the scenario where the user account was created, renamed,
    # or toggled the stealth configuration off and back on again after
    # July 18, 2017, and then made contributions afterward.
    test "finds records with normalized stealth emails" do
      # Change the contributor email to a stealth email with "username" hardcoded
      # e.g. 123456789+username@users.noreply.github.com
      stealth_contribution = @acv_contribution
      stealth_contribution.contributor_email = "#{@user.id}+username@#{GitHub.stealth_email_host_name}"
      stealth_contribution.save!

      assert_same_elements(@acv_repos.pluck(:id), @user.all_acv_repository_ids)
    end

    # This represents the scenario where the user had a stealth email enabled
    # prior to July 18, 2017, and made contributions either before or after
    # that date but before renaming their account and/or toggling the stealth
    # configuration off and back on again.
    test "finds records with legacy stealth emails" do
      # Get a legacy stealth email for the user
      # e.g. myUsername@users.noreply.github.com
      legacy_email = StealthEmail.new(@user).legacy_email

      # Replace the user's active anonymous email with the legacy format
      email_object = @user.emails.build(email: legacy_email, allow_stealth: true)
      email_object.email_roles.build(role: "stealth", user: @user)
      email_object.save!

      # Change the contributor email to the legacy stealth email
      stealth_contribution = @acv_contribution
      stealth_contribution.contributor_email = legacy_email
      stealth_contribution.save!

      assert_same_elements(@acv_repos.pluck(:id), @user.all_acv_repository_ids)
    end

    # This represents the scenario where the user had a stealth email enabled
    # and made contributions with it during the legacy format times (e.g. prior
    # to July 18, 2017) and then later renamed their account or toggled the
    # the stealth configuration off and back on again.
    test "finds records with both normalized and legacy stealth emails" do
      # Get a legacy stealth email for the user
      # e.g. myUsername@users.noreply.github.com
      legacy_email = StealthEmail.new(@user).legacy_email

      # Change the contributor email to the legacy stealth email
      legacy_stealth_contribution = @acv_contribution
      legacy_stealth_contribution.contributor_email = legacy_email
      legacy_stealth_contribution.save!

      # Change the contributor email to a stealth email with "username" hardcoded
      modern_stealth_contribution = @another_acv_contribution
      modern_stealth_contribution.contributor_email = "#{@user.id}+username@#{GitHub.stealth_email_host_name}"
      modern_stealth_contribution.save!

      assert_same_elements(@acv_repos.pluck(:id), @user.all_acv_repository_ids)
    end
  end

  context "#acv_contribution_count" do
    test "returns number of filtered ACV repositories the user contributed to" do
      assert_equal(@acv_repos.length, @user.acv_contribution_count)
    end

    test "counts public repos only" do
      privatized_repo = @acv_repo
      privatized_repo.public = false
      privatized_repo.save!

      assert_equal(@acv_repos.length - 1, @user.acv_contribution_count)
    end

    test "includes repos owned by users that have been blocked from count" do
      blocked_repo = @acv_repo
      @user.block(blocked_repo.owner)
      assert_equal(@acv_repos.length, @user.acv_contribution_count)
    end

    test "includes repos owned by users that have blocked this user from count" do
      blocked_repo = @acv_repo
      blocked_repo.owner.block(@user)
      assert_equal(@acv_repos.length, @user.acv_contribution_count)
    end

    unless GitHub.enterprise?
      test "counts opted-in repos only" do
        opted_out_repo = @acv_repo
        opted_out_repo.enable_archive_program_opt_out(actor: opted_out_repo.owner)

        assert_equal(@acv_repos.length - 1, @user.acv_contribution_count)
      end
    end
  end

  context "#metadata" do
    test "returns the metadata record when it exists" do
      metadata = create(:user_metadata, user: @user)

      assert_equal metadata, @user.metadata
    end

    test "returns a new metadata record when it does not exist" do
      metadata = @user.metadata

      assert_instance_of UserMetadata, metadata
      assert_equal @user, metadata.user
    end
  end

  context "#top_acv_repositories" do
    test "returns a limited list of filtered ACV repositories the user contributed to, sorted by star count" do
      create(:user_metadata, user: @user, has_acv_badge: true)
      @acv_repos[1..5].each_with_index do |repo, index|
        repo.stargazer_count = (index + 1) * 10
        repo.save!
      end

      sorted_acv_repos = @user.top_acv_repositories(limit: 5)

      assert_equal(5, sorted_acv_repos.length)
      assert_equal(@acv_repos[1..5].reverse, sorted_acv_repos)
    end

    test "returns public repos only" do
      create(:user_metadata, user: @user, has_acv_badge: true)
      privatized_repo = @acv_repo
      privatized_repo.public = false
      privatized_repo.stargazer_count = 10
      privatized_repo.save!

      refute_includes(@user.top_acv_repositories, privatized_repo)
    end

    test "excludes repos owned by users that have been blocked" do
      create(:user_metadata, user: @user, has_acv_badge: true)

      blocked_repo = @acv_repo
      @user.block(blocked_repo.owner)
      refute_includes(@user.top_acv_repositories, blocked_repo)
    end

    test "excludes repos owned by users that have blocked this user" do
      create(:user_metadata, user: @user, has_acv_badge: true)

      blocked_repo = @acv_repo
      blocked_repo.owner.block(@user)
      refute_includes(@user.top_acv_repositories, blocked_repo)
    end

    unless GitHub.enterprise?
      test "returns opted-in repos only" do
        create(:user_metadata, user: @user, has_acv_badge: true)
        opted_out_repo = @acv_repo
        opted_out_repo.stargazer_count = 10
        opted_out_repo.save!
        opted_out_repo.enable_archive_program_opt_out(actor: opted_out_repo.owner)

        refute_includes(@user.top_acv_repositories, opted_out_repo)
      end
    end

    test "returns empty array if user is not an ACV contributor" do
      another_user = create(:user)

      assert_equal([], another_user.top_acv_repositories)
    end
  end

  context "#has_profile_highlights?" do
    test "returns true if user has contributions" do
      badge = create(:profile_highlight, user: @user)
      email = create(:user_email, :verified, user: @user)
      repo = create(:repository)
      create(:profile_highlight_contribution, profile_highlight: badge, repository: repo, contributor_email: email)

      assert_equal true, @user.has_profile_highlights?
    end

    test "returns false if user has disabled all badges" do
      badge = create(:profile_highlight, user: @user, hidden: true)
      email = create(:user_email, :verified, user: @user)
      repo = create(:repository)
      create(:profile_highlight_contribution, profile_highlight: badge, repository: repo, contributor_email: email)

      assert_equal false, @user.has_profile_highlights?
    end

    test "returns false if user does not have contributions" do
      rando = create(:user)
      assert_equal false, rando.has_profile_highlights?
    end

    test "returns false for the ghost user even if it has contributions attributed" do
      ghost = User.ghost
      badge = create(:profile_highlight, user: ghost)
      repo = create(:repository)
      create(:profile_highlight_contribution, profile_highlight: badge, repository: repo, contributor_email: ghost.emails.first)

      assert_equal false, ghost.has_profile_highlights?
    end
  end
end
