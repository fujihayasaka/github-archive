# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInvitationRequestTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @invitee = create(:user, login: "invitee")
    @direct_member = create(:user, login: "direct-member")
    @org = create(:organization, admin: @owner)
    @org.add_member(@direct_member)
  end

  context "#invalid?" do
    test "if invite status is invalid, returns true" do
      invalid_invitee = @direct_member.login
      request = OrganizationInvitationRequest.new(
        login: invalid_invitee,
        organization: @org,
        current_user: @owner,
        email: "",
        start_fresh: "",
      )

      assert_equal true, request.invalid?
    end

    test "if invite status is valid, returns false" do
      valid_invitee = @invitee.login
      request = OrganizationInvitationRequest.new(
        login: valid_invitee,
        organization: @org,
        current_user: @owner,
        email: "",
        start_fresh: "",
      )

      assert_equal false, request.invalid?
    end
  end

  context "#reinstating_membership?" do
    test "if inviting by email, returns false" do
      request = OrganizationInvitationRequest.new(
        email: "email@example.com",
        organization: @org,
        current_user: @owner,
        login: "",
        start_fresh: "",
      )

      assert_equal false, request.reinstating_membership?
    end

    test "if starting fresh, returns false" do
      request = OrganizationInvitationRequest.new(
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        email: "",
        start_fresh: true,
      )

      assert_equal false, request.reinstating_membership?
    end

    test "if reinstating, returns true if restorables exist for invitee" do
      restorable_org_user = create(:restorable_organization_user, :complete)
      invitee = restorable_org_user.user
      org = restorable_org_user.organization
      request = OrganizationInvitationRequest.new(
        login: invitee.login,
        organization: org,
        current_user: org.admin,
        email: "",
        start_fresh: "",
      )

      assert_equal true, request.reinstating_membership?
    end

    test "if reinstating, returns false if no restorables exist for invitee" do
      assert_equal 0, Restorable.count
      request = OrganizationInvitationRequest.new(
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        email: "",
        start_fresh: "",
      )

      assert_equal false, request.reinstating_membership?
    end
  end

  context "#inviting_by_email?" do
    test "if given a valid email address, returns true" do
      request = OrganizationInvitationRequest.new(
        email: "email@example.com",
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal true, request.inviting_by_email?
    end

    test "if given an invalid email address, returns false" do
      request = OrganizationInvitationRequest.new(
        email: "email-example.com",
        login: "",
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal false, request.inviting_by_email?
    end

    test "if not given an email address, returns false" do
      request = OrganizationInvitationRequest.new(
        email: "",
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal false, request.inviting_by_email?
    end
  end

  context "#invitation" do
    test "returns existing invitation for user" do
      invite = create(:organization_invitation, organization: @org, invitee: @invitee)

      request = OrganizationInvitationRequest.new(
        email: "",
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal invite, request.invitation
    end

    test "returns existing invitation for an email" do
      invite = create(:organization_invitation, :email, organization: @org, email: @invitee.primary_user_email.email)

      request = OrganizationInvitationRequest.new(
        email: @invitee.primary_user_email.email,
        login: nil,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal invite, request.invitation
    end

    test "returns existing invitation for a private email" do
      @invitee.primary_user_email.toggle_visibility
      refute @invitee.primary_user_email.public?

      invite = create(:organization_invitation, :email, organization: @org, email: @invitee.primary_user_email.email)

      request = OrganizationInvitationRequest.new(
        email: @invitee.primary_user_email.email,
        login: nil,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_equal invite, request.invitation
    end

    test "does not return an existing private email invite for a user" do
      @invitee.primary_user_email.toggle_visibility
      refute @invitee.primary_user_email.public?

      invite = create(:organization_invitation, :email, organization: @org, email: @invitee.primary_user_email.email)

      request = OrganizationInvitationRequest.new(
        email: "",
        login: @invitee.login,
        organization: @org,
        current_user: @owner,
        start_fresh: "",
      )

      assert_nil request.invitation
    end
  end
end
