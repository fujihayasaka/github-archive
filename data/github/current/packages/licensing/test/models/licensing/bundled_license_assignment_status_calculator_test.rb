# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::BundledLicenseAssignmentStatusCalculatorTest < GitHub::TestCase
  fixtures do
    business = create(:business)
    organization = create(:organization, business: business)
    private_repository = create(:private_repository, owner: organization)
    business.reload # make business aware of organization
    user = create(:user)
    email = "email@example.com"
    @organization_invitation = create(:organization_invitation, :email, organization: organization, email: email)
    @repository_invitation = create(:repository_invitation, :email, repository: private_repository, email: email)
    @assignment = create(:licensing_bundled_license_assignment, email: email, user: user, business: business)
  end

  test "returns :license_revoked when the assignment as been revoked" do
    @assignment.update!(revoked: true)

    assert_equal :license_revoked, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :assignment_linked_to_user when the assignment has a user linked and is not revoked" do
    assert_equal :assignment_linked_to_user, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :invited_to_org when the assignment's email has a pending invitation to an organization in the business, does not have a user associated with it yet, and is not revoked" do
    @assignment.update!(user: nil)

    assert_equal :invited_to_org, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :invited_to_repo when the assignment's email has a pending invitation to a repo but not an organization in the business, does not have a user associated with it yet, and is not revoked" do
    @assignment.update!(user: nil)
    @organization_invitation.destroy!

    assert_equal :invited_to_repo, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :linked_to_enterprise_account when there are no pending invitations, no user is linked, and the assignment is not revoked" do
    @assignment.update!(user: nil)
    @organization_invitation.destroy!
    @repository_invitation.destroy!

    assert_equal :linked_to_enterprise_account, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :pending_account_setup when there is no linked business and the assignment has not been revoked" do
    @assignment.update!(user: nil, business: nil)

    assert_equal :pending_account_setup, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment)
  end

  test "returns :declined_org_invite when there is a linked business but no pending invitations or linked user and that status is requested" do
    @assignment.update!(user: nil)
    @organization_invitation.destroy!
    @repository_invitation.destroy!

    assert_equal :declined_org_invite, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment, requested_status: :declined_org_invite)
  end

  test "returns :assignment_linked_to_user when there is a linked business and user and the :declined_org_invite status is requested" do
    assert_equal :assignment_linked_to_user, Licensing::BundledLicenseAssignmentStatusCalculator.calculate_highest_priority(@assignment, requested_status: :declined_org_invite)
  end
end if GitHub.billing_enabled?
