# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInvitationDeduplicatorcallTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @acceptor = create(:verified_user)
    @acceptor.add_email("unverified@example.com")
    @org = create(:organization)
    @email_invitation = create(
      :organization_invitation,
      :email,
      organization: @org,
      email: @acceptor.email,
    )
    @duplicate_email_invitation = create(
      :organization_invitation,
      :email,
      organization: @org,
      email: @acceptor.email,
    )
    @user_invitation = create(
      :organization_invitation,
      organization: @org,
      invitee: @acceptor,
    )
    @duplicate_user_invitation = create(
      :organization_invitation,
      organization: @org,
      invitee: @acceptor,
    )
  end

  test "cancels all duplicates if deduplicating an email invitation" do
    result = subject.call!(invitation: @email_invitation, acceptor: @acceptor)

    assert result
    assert_predicate @duplicate_email_invitation.reload, :cancelled?
    assert_predicate @user_invitation.reload, :cancelled?
    assert_predicate @duplicate_user_invitation.reload, :cancelled?
  end

  test "cancels all duplicates if deduplicating a user invitation, if feature flag is turned on" do
    result = subject.call!(invitation: @user_invitation, acceptor: @acceptor)

    assert result
    assert_predicate @email_invitation.reload, :cancelled?
    assert_predicate @duplicate_email_invitation.reload, :cancelled?
    assert_predicate @duplicate_user_invitation.reload, :cancelled?
  end

  test "does not cancel non-duplicate" do
    subject.call!(invitation: @email_invitation, acceptor: @acceptor)
    refute_predicate @email_invitation.reload, :cancelled?
  end

  test "invitation sent to an unverified email address is not marked as a duplicate, doesn't get cancelled, if feature flag is turned on" do
    unverified_email_invitation = create(
      :organization_invitation,
      :email,
      organization: @org,
      email: @acceptor.emails.unverified.first.email,
    )

    subject.call!(invitation: @email_invitation, acceptor: @acceptor)

    refute_predicate unverified_email_invitation.reload, :cancelled?
  end

  test "does not transfer team_invitations to the non-duplicate" \
    "if the invitation is to an unverified email" do
    acceptor = create(:user)
    org = create(:organization)
    invitation = create(
      :organization_invitation,
      :email,
      organization: org,
      email: acceptor.email,
    )
    duplicate_invitation = create(
      :organization_invitation,
      :email,
      organization: @org,
      email: @acceptor.email,
    )
    team_invitation = create(
      :team_invitation,
      organization_invitation: duplicate_invitation,
    )
    subject.call!(invitation: invitation, acceptor: acceptor)
    refute_includes invitation.teams, team_invitation.team
  end

  test "transfers all team_invitations to the non-duplicate" \
    "if the invitation is to a verified email" do
    team_invitation = create(
      :team_invitation,
      organization_invitation: @duplicate_email_invitation,
    )
    subject.call!(invitation: @email_invitation, acceptor: @acceptor)
    assert_includes @email_invitation.teams, team_invitation.team
  end

  test "transfers all team_invitations to the non-duplicate" \
    "if the invitation is to a user" do
    team_invitation = create(
      :team_invitation,
      organization_invitation: @duplicate_user_invitation,
    )
    subject.call!(invitation: @email_invitation, acceptor: @acceptor)
    assert_includes @email_invitation.teams, team_invitation.team
  end

  test "logs that there are duplicates" do
    assert_logged Body: "duplicate_organization_invitations" do
      subject.call!(invitation: @email_invitation, acceptor: @acceptor)
    end
  end

  test "noops when there are no duplicates" do
    acceptor = create(:user)
    invitation = create(
      :organization_invitation,
      organization: @org,
      invitee: acceptor,
    )
    assert subject.call!(invitation: invitation, acceptor: acceptor)
    assert_equal 1, OrganizationInvitation
      .where(invitee: acceptor)
      .where(cancelled_at: nil)
      .count
  end

  def subject
    OrganizationInvitation::Deduplicator
  end
end unless GitHub.bypass_org_invites_enabled? # invites are disabled in GHES
