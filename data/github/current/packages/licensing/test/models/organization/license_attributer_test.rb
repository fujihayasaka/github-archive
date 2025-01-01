# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationLicenseAttributerTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @organization_admin = @organization.admins.first
  end

  context "#user_ids" do
    test "includes organization admins" do
      assert_includes Organization::LicenseAttributer.new(@organization).user_ids, @organization_admin.id
    end

    test "includes the initial organization admins that won't be linked to the organization until after the creation has been committed" do
      admin = create(:user)
      organization = Organization.new(admins: [admin])

      assert_includes Organization::LicenseAttributer.new(organization).user_ids, admin.id
    end

    test "includes organization members" do
      organization_member_user = create(:user)
      @organization.add_member(organization_member_user, adder: @organization_admin)

      assert_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_member_user.id
    end

    test "includes users who have been invited to the organization by their login" do
      organization_invited_user = create(:user)
      @organization.invite(organization_invited_user, inviter: @organization_admin)

      assert_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_invited_user.id
    end

    test "does not include users who have been invited to the organization by their login more than 7 days ago" do
      organization_invited_user = create(:user)
      travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        @organization.invite(organization_invited_user, inviter: @organization_admin)
      end

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_invited_user.id
    end

    test "includes users who are members of active private repositories owned by the organization" do
      active_private_repository_member_user = create(:user)
      active_private_repository = create(:private_repository, active: true, owner: @organization)
      active_private_repository.add_member(active_private_repository_member_user, @organization_admin)

      assert_includes Organization::LicenseAttributer.new(@organization).user_ids, active_private_repository_member_user.id
    end

    test "includes users who are invited to active private repositories owned by the organization" do
      active_private_repository_invited_user = create(:user)
      active_private_repository = create(:private_repository, active: true, owner: @organization)
      RepositoryInvitation.invite_to_repo(active_private_repository_invited_user, @organization_admin, active_private_repository)

      assert_includes Organization::LicenseAttributer.new(@organization).user_ids, active_private_repository_invited_user.id
    end

    test "does not include users who are invited to active private repositories owned by the organization more than 7 days ago", skip_enterprise: true do
      active_private_repository_invited_user = create(:user)
      active_private_repository = create(:private_repository, active: true, owner: @organization)
      travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        RepositoryInvitation.invite_to_repo(active_private_repository_invited_user, @organization_admin, active_private_repository)
      end

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, active_private_repository_invited_user.id
    end

    test "does not include users who have been invited to the organization via email" do
      organization_invited_user_by_email = create(:user)
      @organization.invite(email: organization_invited_user_by_email.email, inviter: @organization_admin)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_invited_user_by_email.id
    end

    test "does not include invited billing managers" do
      organization_invited_billing_manager = create(:user)
      @organization.invite(organization_invited_billing_manager, inviter: @organization_admin, role: :billing_manager)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_invited_billing_manager.id
    end

    test "does not include billing managers" do
      organization_billing_manager = create(:user)
      @organization.invite(organization_billing_manager, inviter: @organization_admin, role: :billing_manager).
        accept(acceptor: organization_billing_manager)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, organization_billing_manager.id
    end

    test "does not include users who are members of active public repositories owned by the organization" do
      active_public_repository_member_user = create(:user)
      active_public_repository = create(:public_repository, active: true, owner: @organization)
      active_public_repository.add_member(active_public_repository_member_user, @organization_admin)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, active_public_repository_member_user.id
    end

    test "does not include users who are invited to active public repositories owned by the organization" do
      active_public_repository_invited_user = create(:user)
      active_public_repository = create(:public_repository, active: true, owner: @organization)
      RepositoryInvitation.invite_to_repo(active_public_repository_invited_user, @organization_admin, active_public_repository)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, active_public_repository_invited_user.id
    end

    test "does not include users who are members of inactive private repositories owned by the organization" do
      inactive_private_repository_member_user = create(:user)
      inactive_private_repository = create(:private_repository, active: nil, owner: @organization)
      inactive_private_repository.add_member(inactive_private_repository_member_user, @organization_admin)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, inactive_private_repository_member_user.id
    end

    test "does not include users who are invited to inactive private repositories owned by the organization" do
      inactive_private_repository_invited_user = create(:user)
      inactive_private_repository = create(:private_repository, active: nil, owner: @organization)
      RepositoryInvitation.invite_to_repo(inactive_private_repository_invited_user, @organization_admin, inactive_private_repository)

      refute_includes Organization::LicenseAttributer.new(@organization).user_ids, inactive_private_repository_invited_user.id
    end
  end

  context "#emails" do
    test "includes email addresses that have been invited to the organization" do
      invited_email = "invited@example.com"
      @organization.invite(email: invited_email, inviter: @organization_admin)

      assert_includes Organization::LicenseAttributer.new(@organization).emails, invited_email
    end

    test "does not include email addresses that have been invited to the organization more than 7 days ago" do
      invited_email = "invited@example.com"
      travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        @organization.invite(email: invited_email, inviter: @organization_admin)
      end

      refute_includes Organization::LicenseAttributer.new(@organization).emails, invited_email
    end

    test "does not include email addresses of billing manager who have been invited to the organization" do
      billing_manager_email = "billing@example.com"
      @organization.invite(email: billing_manager_email, inviter: @organization_admin, role: :billing_manager)

      refute_includes Organization::LicenseAttributer.new(@organization).emails, billing_manager_email
    end

    test "includes emails that are invited to active private repositories owned by the organization" do
      active_private_repository_invited_email = "invited_collaborator@example.com"
      active_private_repository = create(:private_repository, active: true, owner: @organization)
      RepositoryInvitation.invite_to_repo_by_email(active_private_repository_invited_email, @organization_admin, active_private_repository)

      assert_includes Organization::LicenseAttributer.new(@organization).emails, active_private_repository_invited_email
    end

    test "does not include emails that are invited to active private repositories owned by the organization more than 7 days ago" do
      active_private_repository_invited_email = "invited_collaborator@example.com"
      active_private_repository = create(:private_repository, active: true, owner: @organization)

      travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        RepositoryInvitation.invite_to_repo_by_email(active_private_repository_invited_email, @organization_admin, active_private_repository)
      end

      refute_includes Organization::LicenseAttributer.new(@organization).emails, active_private_repository_invited_email
    end

    test "does not include emails that are invited to active public repositories owned by the organization" do
      active_public_repository_invited_email = "invited_collaborator@example.com"
      active_public_repository = create(:public_repository, active: true, owner: @organization)
      RepositoryInvitation.invite_to_repo_by_email(active_public_repository_invited_email, @organization_admin, active_public_repository)

      refute_includes Organization::LicenseAttributer.new(@organization).emails, active_public_repository_invited_email
    end

    test "does not include emails that are invited to inactive private repositories owned by the organization" do
      inactive_private_repository_invited_email = "invited_collaborator@example.com"
      inactive_private_repository = create(:private_repository, active: nil, owner: @organization)
      RepositoryInvitation.invite_to_repo_by_email(inactive_private_repository_invited_email, @organization_admin, inactive_private_repository)

      refute_includes Organization::LicenseAttributer.new(@organization).emails, inactive_private_repository_invited_email
    end
  end

  context "#unique_count" do
    test "returns the count of licensable user IDs and emails" do
      @organization.invite(email: "invite@example.com", inviter: @organization_admin)

      repository = create(:private_repository, active: true, owner: @organization)
      repository.add_member(@organization_admin)

      # one for @organization_admin, one for the invited email
      assert_equal 2, Organization::LicenseAttributer.new(@organization).unique_count
    end
  end
end
