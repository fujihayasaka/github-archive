# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRemoveAnyAffiliationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @repo = create(:private_repository, :minimal, owner: @org)
  end

  test "removes all affiliations for an organization member" do
    @org.add_member(@user)
    @repo.add_member(@user)
    @org.billing.add_manager(@user, actor: @org.admin)
    assert_includes @org.members, @user
    assert_includes @org.billing_managers, @user
    assert_includes @repo.members, @user

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @org.remove_any_affiliation(@user, actor: @org.admin)
    end

    refute_includes @org.members, @user
    refute_includes @org.billing_managers, @user
    refute_includes @repo.members, @user
  end

  test "removes all affiliations for a billing manager" do
    @org.billing.add_manager(@user, actor: @org.admin)
    @repo.add_member(@user)
    assert_includes @org.billing_managers, @user
    assert_includes @repo.members, @user

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, RemoveOutsideCollaboratorFromOrganizationJob]) do
      @org.remove_any_affiliation(@user, actor: @org.admin)
    end

    refute_includes @org.billing_managers, @user
    refute_includes @repo.members, @user
  end

  if GitHub.user_abuse_mitigation_enabled?
    test "removes all affiliations for a moderator" do
      @org.add_member(@user)
      @org.moderation.add_moderator(@user, actor: @org.admin)

      assert @org.moderation.moderator?(@user)
      assert_includes @org.members, @user

      perform_enqueued_jobs(only: [
        RemoveOrgMemberJob,
        RevokeOrgMembershipAbilitiesJob,
      ]) do
        @org.remove_any_affiliation(@user, actor: @org.admin)
      end

      refute @org.moderation.moderator?(@user)
      refute_includes @org.members, @user
    end
  end

  test "removes all associations for outside collaborator" do
    @repo.add_member(@user)
    assert_includes @repo.members, @user

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, RemoveOutsideCollaboratorFromOrganizationJob]) do
      @org.remove_any_affiliation(@user, actor: @org.admin)
    end

    refute_includes @repo.members, @user
  end

  test "only one restorable is created" do
    @repo.add_member(@user)
    @org.add_member(@user)

    assert_difference "Restorable.count", 1 do
      @org.remove_any_affiliation(@user, actor: @user)
    end
  end

  test "creates a valid restorable when removing user" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This ff does not create restorables
    GitHub.flipper[:remove_org_member_repo_stars_job_use_bulk_ci_only].disable # This feature prevents creation of restorables
    @org.add_member(@user)

    only = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
    ]

    perform_enqueued_jobs(only: only) do
      @org.remove_any_affiliation(@user, actor: @user)
    end

    restorable = Restorable::OrganizationUser.most_recent(@org, @user).first
    assert_predicate restorable, :restorable?
  end

  test "does not create a restorable for users without org affiliation" do
    only = [
      RemoveOrgMemberJob,
      RevokeOrgMembershipAbilitiesJob,
      RemoveOrgMemberForksJob,
      RemoveOrgMemberWatchedRepositoriesJob,
      RemoveOrgMemberRepositoryStarsJob,
      RemoveOrgMemberIssueAssignmentsJob,
      RemoveOrgMemberVulnerabilityManagementJob,
      RemoveOrgMemberPackageAccessJob,
    ]

    perform_enqueued_jobs(only: only) do
      @org.remove_any_affiliation(@user, actor: @user)
    end

    restorable = Restorable::OrganizationUser.most_recent(@org, @user).first
    assert_nil restorable
  end
end
