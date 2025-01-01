# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInvitationOptOutAssociationsTest < GitHub::TestCase
  fixtures do
    @org          = create(:organization)
    @invitation   = create(:organization_invitation, organization: @org)
    @opt_out      = create(:organization_invitation_opt_out,
      organization: @org,
      organization_invitation: @invitation,
      email: "email@example.com",
    )
  end

  test "belongs_to organizations and invitations when saved" do
    refute_predicate @opt_out, :new_record?

    assert_equal @org, @opt_out.organization
    assert_equal @invitation, @opt_out.organization_invitation
  end

  context "idempotent opt outs" do
    test "does not create duplicate opt outs for the same org/invitation/email" do
      invitation = create(:organization_invitation, organization: @org, invitee: nil, email: "invitee@example.com")

      assert_difference("OrganizationInvitation::OptOut.count", 1) do
        opt_out_one = OrganizationInvitation::OptOut.opt_out(org: @org, invitation: invitation, email: "invitee@example.com")
        opt_out_two = OrganizationInvitation::OptOut.opt_out(org: @org, invitation: invitation, email: "invitee@example.com")

        assert_equal opt_out_one, opt_out_two
      end
    end
  end
end

class OrganizationInvitationOptOutoptedOutTest < GitHub::TestCase
  fixtures do
    @org_admin    = create(:user, login: "org-admin")
    @org          = create(:organization, admin: @org_admin)
    @invitation   = create(:organization_invitation, organization: @org)
  end

  test "returns true when an email address has been opted out" do
    invitation = @org.invite(nil, email: "email@example.com", inviter: @org_admin, role: :direct_member)
    invitation.opt_out(actor: User.ghost)

    assert OrganizationInvitation::OptOut.opted_out?(org: @org, email: "email@example.com"),\
      "should say that 'email@example.com' is opted_out of this org"
  end

  test "returns false when an email address has not opted out" do
    invitation = @org.invite(nil, email: "email@example.com", inviter: @org_admin, role: :direct_member)

    refute OrganizationInvitation::OptOut.opted_out?(org: @org, email: "email@example.com"),\
      "should say that 'email@example.com' is not opted_out of this org"
  end

  test "returns true when any verified email of a user has been opted out" do
    invitee = create(:user, email: "invitee@example.com")
    invitee.add_email("email_2@example.com")
    invitee.add_email("email_3@example.com")
    invitee.emails.each(&:verify!)

    invitation = @org.invite(invitee, inviter: @org_admin, role: :direct_member)
    invitation.opt_out(actor: invitee)

    UserEmail.safe_bulk_normalize(users: invitee).each do |email|
      assert OrganizationInvitation::OptOut.opted_out?(org: @org, email: email),
        "should say that '#{email}' is opted_out of this org"
    end

    assert OrganizationInvitation::OptOut.opted_out?(org: @org, invitee: invitee),
      "should say that '#{invitee}' is opted_out of this org"
  end
end

class OrganizationInvitationOptOutgroupedByInvitationTest < GitHub::TestCase
  fixtures do
    @opt_out = create(:organization_invitation_opt_out)
    @org = create(:organization)
  end

  test "returns a list of opt outs by invitation" do
    opted_out_invitations = OrganizationInvitation::OptOut.grouped_by_invitation(org: @opt_out.organization)

    assert_equal @opt_out.organization_invitation.id, opted_out_invitations.first[0]
    assert_equal @opt_out.email, opted_out_invitations.first[1][0].email
  end

  test "returns an empty hash if there are no opt outs" do
    opted_out_invitations = OrganizationInvitation::OptOut.grouped_by_invitation(org: @org)

    refute opted_out_invitations.present?
  end
end

class OrganizationInvitationOptOutValidationsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @invitation = create(:organization_invitation, organization: @org)
  end

  test "can be valid" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: @org,
      organization_invitation: @invitation,
      email: "email@example.com",
    )

    assert_predicate opt_out, :valid?
  end

  test "requires an organization" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: nil,
      organization_invitation: @invitation,
      email: "email@example.com",
    )

    refute_predicate opt_out, :valid?, "should require an organization"
  end

  test "requires an email" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: @org,
      organization_invitation: @invitation,
      email: nil,
    )

    refute_predicate opt_out, :valid?, "should require an email"
    assert_predicate opt_out.errors[:email], :any?
  end

  test "requires an email longer than 2 characters" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: @org,
      organization_invitation: @invitation,
      email: "a@",
    )

    refute_predicate opt_out, :valid?, "should require a valid email"
    assert_predicate opt_out.errors[:email], :any?
  end

  test "requires an email no longer than 100 characters" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: @org,
      organization_invitation: @invitation,
      email: "#{"a" * 100}@example.com",
    )

    refute_predicate opt_out, :valid?, "should require a valid email"
    assert_predicate opt_out.errors[:email], :any?
  end

  test "requires an email in the correct format" do
    opt_out = OrganizationInvitation::OptOut.new(
      organization: @org,
      organization_invitation: @invitation,
      email: "abc_at_example.com",
    )

    refute_predicate opt_out, :valid?, "should require a valid email"
    assert_predicate opt_out.errors[:email], :any?
  end
end
