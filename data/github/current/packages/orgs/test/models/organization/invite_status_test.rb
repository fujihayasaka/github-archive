# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInviteStatusTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization, login: "the-org")
    @admin   = @org.admin
    @team    = create(:team, organization: @org, name: "the-team")
    @invitee = create(:user, login: "invitee")
    @invitee.emails.each(&:verify!)
  end

  context "errors" do
    test "is empty for an unassociated invitee and teams" do
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, teams: [@team])
      assert_empty status.errors
    end

    test "is empty for an already-invited invitee" do
      @org.invite(@invitee, inviter: @admin, teams: [@team])
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, teams: [@team])

      assert_empty status.errors
    end

    test "is empty for an unassociated invitee and no teams" do
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, teams: [])
      assert_empty status.errors
    end

    test "is empty for a member invited as a billing manager" do
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, role: :billing_manager)
      assert_empty status.errors
    end

    test "is empty for an email invited as a billing manager" do
      status = Organization::InviteStatus.new(@org, email: "manager@github.com", inviter: @admin, role: :billing_manager)
      assert_empty status.errors
    end

    test "is :invalid_teams for an unassociated invitee and different-org teams" do
      different_org_team = create(:team, name: "different-org-team")
      status             = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, teams: [different_org_team])

      assert_same_elements [:invalid_teams, :insufficient_inviter_permissions], status.errors
    end

    test "is :already_on_org for an org member invitee" do
      @org.add_member(@invitee)
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, teams: [@team])

      assert_equal [:already_on_org], status.errors
    end

    test "is :invitee_is_not_a_user for an organization invitee" do
      bad_invitee = create(:organization, login: "bad-invitee")
      status      = Organization::InviteStatus.new(@org, bad_invitee, inviter: @admin, teams: [@team])

      assert_equal [:invitee_is_not_a_user], status.errors
    end

    test "is :invitee_is_not_a_user when invitee is a bot" do
      bot = create(:integration).bot
      status = Organization::InviteStatus.new(@org, bot, inviter: @admin, teams: [@team])

      assert_equal [:invitee_is_not_a_user], status.errors
    end

    test "is :insufficient_inviter_permissions for a team maintainer inviter" do
      team_maintainer = create(:user, login: "team-maintainer")
      @org.add_member(team_maintainer)
      @team.add_member(team_maintainer)
      @team.promote_maintainer(team_maintainer)

      status = Organization::InviteStatus.new(@org, @invitee, inviter: team_maintainer, teams: [@team])

      assert_equal [:insufficient_inviter_permissions], status.errors
    end

    test "is :already_has_role for an existing billing manager invited as a billing manager" do
      billing_manager = create(:user, login: "billing-pro")
      @org.billing.add_manager(billing_manager, actor: @admin)

      status = Organization::InviteStatus.new(@org, billing_manager, inviter: @admin, role: :billing_manager)

      assert_equal [:already_has_role], status.errors
    end

    test "is :invitee_and_email_provided when invitee and email is provided" do
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin, email: "garrett@github.com")

      assert_equal [:invitee_and_email_provided], status.errors
    end

    test "is :invitee_or_email_required when invitee and email is not provided" do
      status = Organization::InviteStatus.new(@org, nil, inviter: @admin, email: nil)

      assert_equal [:invitee_or_email_required], status.errors
    end

    test "is :invitee_opted_out when non-user has opted out of invitations from this organization" do
      invitation = create(:organization_invitation,
        organization: @org,
        inviter: @admin,
        invitee: nil,
        email: "opt-out@example.com",
      )

      invitation.opt_out(actor: @admin)

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: "opt-out@example.com", inviter: @admin)

      assert_equal [:invitee_opted_out], status.errors
    end

    test "is :invitee_opted_out when invitee has opted out of invitations from this organization" do
      invitee = create(:user, email: "invitee@example.com")
      invitee.emails.each(&:verify!)
      invitation = create(:organization_invitation,
        organization: @org,
        inviter: @admin,
        invitee: invitee,
      )

      invitation.opt_out(actor: @admin)

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: invitee, inviter: @admin)

      assert_equal [:invitee_opted_out], status.errors
    end

    test "is :invalid_email when email is prefixed with mailto:" do
      prefixed_email = "mailto:foo@bar.com"

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: prefixed_email, inviter: @admin)

      assert_equal [:invalid_email], status.errors
    end

    test "is :invitee_or_email_required when email is not valid" do
      invalid_email = "meow"
      refute User.valid_email?(invalid_email), "should be an invalid email"

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: invalid_email, inviter: @admin)

      assert_equal [:invitee_or_email_required], status.errors
    end

    test "is :invalid_email when email provided ends with a trailing dot" do
      trailing_dot_email = "foo@bar.com."

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: trailing_dot_email, inviter: @admin)

      assert_equal [:invalid_email], status.errors
    end

    test "checks that a user blocked by org admin can be invited to org" do
      # Make an org admin block the user
      @admin.block(@invitee)

      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin)

      assert_empty status.errors
    end

    test "checks that a user blocked by the org can not be invited to the org" do
      # Make the org block the user
      @org.block(@invitee)

      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin)

      assert_equal [:blocked_from_org], status.errors
    end

    if GitHub.email_verification_enabled?
      test "is :inviter_requires_verification if the inviter requires verification" do
        owner = @admin
        owner.add_email("john+forceverify@github.com")

        status = Organization::InviteStatus.new(@org, nil, email: "other@example.com", inviter: owner)

        assert_equal [:inviter_requires_verification], status.errors
      end
    end

    test "is :no_teams_while_reinstating when specifying teams while role is reinstate" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], role: :reinstate, inviter: @admin)

      assert_equal [:no_teams_while_reinstating], status.errors
    end

    test "can have multiple errors" do
      # Make the invitee already a member
      @org.add_member(@invitee)

      # Make a team on a different org
      different_team = create(:team, name: "different-team")

      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team, different_team], inviter: @admin)

      assert_same_elements [:already_on_org, :invalid_teams, :insufficient_inviter_permissions], status.errors
    end
  end

  context "valid?" do
    test "is true for an unassociated invitee and teams" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)
      assert status.valid?
    end

    test "is true for an already-invited invitee" do
      @org.invite(@invitee, inviter: @admin, teams: [@team])
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)

      assert status.valid?
    end

    test "is true for an unassociated invitee and no teams" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [], inviter: @admin)
      assert status.valid?
    end

    test "is true when an email is provided" do
      status = Organization::InviteStatus.new(@org, email: "garrett@github.com", inviter: @admin)
      assert status.valid?
    end

    test "is false when invitee and email is provided" do
      status = Organization::InviteStatus.new(@org, @invitee, email: "garrett@github.com", inviter: @admin)
      refute status.valid?
    end

    test "is false when invitee or email is not provided" do
      status = Organization::InviteStatus.new(@org, nil, email: nil, inviter: @admin)
      refute status.valid?
    end

    test "is false for an unassociated invitee and different-org teams" do
      different_org_team = create(:team, name: "different-org-team")
      status             = Organization::InviteStatus.new(@org, @invitee, teams: [different_org_team], inviter: @admin)

      refute status.valid?
    end

    test "is false for an org member invitee" do
      @org.add_member(@invitee)
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)

      refute status.valid?
    end

    test "is false for an organization invitee" do
      bad_invitee = create(:organization, login: "bad-invitee")
      status      = Organization::InviteStatus.new(@org, bad_invitee, teams: [@team], inviter: @admin)

      refute status.valid?
    end

    test "is false for a team maintainer inviter" do
      team_maintainer = create(:user, login: "team-maintainer")
      @org.add_member(team_maintainer)
      @team.add_member(team_maintainer)
      @team.promote_maintainer(team_maintainer)

      status = Organization::InviteStatus.new(@org, @invitee, inviter: team_maintainer, teams: [@team])

      refute status.valid?
    end

    test "is false when email with trailing dot provided" do
      status = Organization::InviteStatus.new(@org, @invitee, email: "garrett@github.com.", inviter: @admin)
      refute status.valid?
    end
  end

  context "validate!" do
    test "is true for an unassociated invitee and teams" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)
      assert status.validate!
    end

    test "is true for an already-invited invitee" do
      @org.invite(@invitee, inviter: @admin, teams: [@team])
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)

      assert status.validate!
    end

    test "is true for an unassociated invitee and no teams" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [], inviter: @admin)
      assert status.validate!
    end

    test "is true when an email is provided and the email address is not opted out" do
      status = Organization::InviteStatus.new(@org, email: "garrett@github.com", inviter: @admin)
      assert status.validate!
    end

    test "raises OrganizationInvitation::InvalidError when invitee and email is provided" do
      status = Organization::InviteStatus.new(@org, @invitee, email: "garrett@github.com", inviter: @admin)
      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError when invitee or email is not provided" do
      status = Organization::InviteStatus.new(@org, nil, email: nil, inviter: @admin)
      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError when email with trailing dot provided" do
      status = Organization::InviteStatus.new(@org, email: "garrett@github.com.", inviter: @admin)
      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for an unassociated invitee and different-org teams" do
      different_org_team = create(:team, name: "different-org-team")
      status             = Organization::InviteStatus.new(@org, @invitee, teams: [different_org_team], inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for an org member invitee" do
      @org.add_member(@invitee)
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for an organization invitee" do
      bad_invitee = create(:organization, login: "bad-invitee")
      status      = Organization::InviteStatus.new(@org, bad_invitee, teams: [@team], inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    if GitHub.email_verification_enabled?
      test "raises OrganizationInvitation::InvalidError for an inviter that requires email verification" do
        owner = @admin
        owner.add_email("john+forceverify@github.com")

        status = Organization::InviteStatus.new(@org, nil, email: "other@example.com", inviter: owner)

        assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
      end
    end

    test "raises OrganizationInvitation::InvalidError for when specifying teams while role is reinstate" do
      status = Organization::InviteStatus.new(@org, @invitee, teams: [@team], role: :reinstate, inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for a team maintainer inviter" do
      team_maintainer = create(:user, login: "team-maintainer")
      @org.add_member(team_maintainer)
      @team.add_member(team_maintainer)
      @team.promote_maintainer(team_maintainer)

      status = Organization::InviteStatus.new(@org, @invitee, inviter: team_maintainer, teams: [@team])

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for an opted out invitee" do
      invitation = create(:organization_invitation,
        organization: @org,
        invitee: nil,
        email: "opt-out@example.com",
      )
      invitation.opt_out(actor: @admin)

      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: "opt-out@example.com", inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end

    test "raises OrganizationInvitation::InvalidError for an invitee who is blocked by the org" do
      @org.block(@invitee)
      status = Organization::InviteStatus.new(@org, @invitee, inviter: @admin)

      assert_raises(OrganizationInvitation::InvalidError) { status.validate! }
    end
  end

  context ".build_by_email_or_user" do
    test "given a User object, returns a status object" do
      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: @invitee, inviter: @admin)

      assert_equal Organization::InviteStatus, status.class
      assert_predicate status, :valid?
    end

    test "given a valid email string, returns a status object" do
      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: "u@email.com", inviter: @admin)

      assert_equal Organization::InviteStatus, status.class
      assert_predicate status, :valid?
    end

    test "given neither a User nor a valid email, returns a null object" do
      status = Organization::InviteStatus.build_by_email_or_user(@org, invitee: "not-an-email", inviter: @admin)

      assert_equal Organization::InvalidInviteStatus, status.class
      refute_predicate status, :valid?
      refute_predicate status, :present?
      assert_predicate status, :blank?
      assert_nil status
    end
  end
end
