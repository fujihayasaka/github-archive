# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationLicenseHolderTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @organization_admin = @organization.admins.first

    @member = create(:user)
    @organization.add_member(@member, adder: @organization_admin)

    @collaborator = create(:user)
    repository = create(:private_repository, active: true, owner: @organization)
    repository.add_member(@collaborator)

    @invited_collaborator = create(:user)
    RepositoryInvitation.invite_to_repo(@invited_collaborator, @organization_admin, repository)

    @invited_member = create(:user)
    @organization.invite(@invited_member, inviter: @organization_admin)

    @invited_email = "fox.mulder@github.com"
    @organization.invite(email: @invited_email.titleize, inviter: @organization_admin)
    RepositoryInvitation.invite_to_repo_by_email(@invited_email.upcase, @organization_admin, repository)

    @repo_invited_email = "fawazfarid@github.com"
    RepositoryInvitation.invite_to_repo_by_email(@repo_invited_email, @organization_admin, repository)
  end

  context "#users" do
    test "includes all users and excludes emails" do
      license_holders = Organization::LicenseHolder.new(@organization)

      assert_includes license_holders.users.values, @member.id
      assert_includes license_holders.users.values, @organization_admin.id
      assert_includes license_holders.users.values, @collaborator.id
      assert_includes license_holders.users.values, @invited_collaborator.id
      assert_includes license_holders.users.values, @invited_member.id
      refute_includes license_holders.users.values, @invited_email
      refute_includes license_holders.users.values, @repo_invited_email
    end
  end

  context "#emails" do
    test "includes only invited emails" do
      license_holders = Organization::LicenseHolder.new(@organization)

      refute_includes license_holders.emails.values, @member.id
      refute_includes license_holders.emails.values, @organization_admin.id
      refute_includes license_holders.emails.values, @collaborator.id
      refute_includes license_holders.emails.values, @invited_collaborator.id
      refute_includes license_holders.emails.values, @invited_member.id
      assert_includes license_holders.emails.values, @invited_email
      refute_includes license_holders.emails.values, @invited_email.titleize
      refute_includes license_holders.emails.values, @invited_email.upcase
      assert_includes license_holders.emails.values, @repo_invited_email
    end
  end
end unless GitHub.enterprise?
