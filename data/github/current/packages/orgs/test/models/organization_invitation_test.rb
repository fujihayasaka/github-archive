# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInvitationCallbacksTest < GitHub::TestCase
  include ActionMailer::TestHelper

  fixtures do
    @org = create(:organization)
    @inviter = @org.admins.last
    @invitee = create(:user)
    @invitee.emails.each(&:verify!)
  end

  setup do
    deliveries.clear
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  context "#failed_reason_description" do
    test "returns correct description for failed_reason" do
      {
        no_more_seats: "No seats available",
        trade_controls: "This user isn't able to use this feature due to trade regulations",
        already_accepted: "Invitation already accepted",
        invalid_generic: "Invitation is invalid",
        expired: "Invitation expired. User did not accept this invite for 7 days",
      }.each do |key, description|
        invitation = @org.invite(create(:user), inviter: @inviter, role: :direct_member)
        invitation.update failed_reason: key
        assert_predicate invitation, :failed?
        assert_equal key.to_s, invitation.failed_reason
        assert_equal description, invitation.failed_reason_description
      end
    end

    test "returns nil when invitation has not failed" do
      invitation = @org.invite(create(:user), inviter: @inviter, role: :direct_member)
      assert_nil invitation.failed_reason_description
    end
  end

  # There are more sophisticated ways to test email queueing in ActionMailer as
  # of rails 5.2 but as of rails 4.2 this is the best we can do without writing
  # our own test helpers.
  # See http://api.rubyonrails.org/v5.2.0/classes/ActionMailer/TestHelper.html
  context "after_commit on create" do
    if GitHub.spamminess_check_enabled?
      test "does nothing if inviter is spammy" do
        @inviter.update_attribute(:spammy, true)

        assert_no_enqueued_jobs(only: ApplicationDeliveryJob) do
          OrganizationInvitation.create!(
            organization: @org,
            invitee: @invitee,
            inviter: @inviter,
            role: :direct_member,
          )
        end
      end
    end

    if GitHub.billing_enabled?
      test "queues the billing manager email" do
        # It's possible to check args in these asserts, but that would require
        # the persisted invitation and this code is triggered in the
        # after_commit on: :create  callback so that's impossible
        assert_performed_with job: ApplicationDeliveryJob, queue: ApplicationDeliveryJob.queue_name do
          OrganizationInvitation.create!(
            organization: @org,
            invitee: @invitee,
            inviter: @inviter,
            role: :billing_manager,
          )

          email = deliveries.shift
          assert_equal "[GitHub] @#{@inviter.login} has invited you to be a billing manager for the @#{@org.login} organization", email.subject
        end
      end
    end

    test "queues the invited by email email" do
      assert_performed_with job: ApplicationDeliveryJob do
        OrganizationInvitation.create!(
          organization: @org,
          email: @invitee.email,
          inviter: @inviter,
          role: :direct_member,
        )

        email = deliveries.shift
        assert_equal "[GitHub] @#{@inviter.login} has invited you to join the @#{@org.login} organization", email.subject
      end
    end

    test "queues the regular org invite email" do
      assert_performed_with job: ApplicationDeliveryJob do
        OrganizationInvitation.create!(
          organization: @org,
          invitee: @invitee,
          inviter: @inviter,
          role: :direct_member,
        )

        email = deliveries.shift
        assert_equal "[GitHub] @#{@inviter.login} has invited you to join the @#{@org.login} organization", email.subject
      end
    end

    test "does nothing if the invitation failed" do
      assert_no_enqueued_emails do
        OrganizationInvitation.create!(
          organization: @org,
          invitee: @invitee,
          inviter: @inviter,
          role: :direct_member,
          failed_reason: :no_more_seats,
        )
      end
    end
  end
end

class ValidationsTest < GitHub::TestCase
  test "invalid if not unique by accepted_at and normalized_email" do
    Timecop.freeze do
      inviter = create(:user)
      invitee = create(:user)
      org = create(:organization)

      old_invitation = create(
        :organization_invitation,
        organization: org,
        inviter: inviter,
        invitee: invitee,
      )

      new_invitation = create(
        :organization_invitation,
        organization: org,
        inviter: inviter,
        invitee: invitee,
      )

      old_invitation.update(accepted_at: Time.now)
      new_invitation.accepted_at = Time.now
      refute_predicate new_invitation, :valid?
      assert_includes new_invitation.errors[:accepted_at], "has already been accepted"
    end
  end
end

class OrganizationInvitationAssociationsTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization)
    @inviter = @org.admins.last
    team = create(:team, organization: @org)

    @invitation      = create(:organization_invitation, organization: @org, inviter: @inviter)
    @team_invitation = @invitation.team_invitations.create(
      inviter: @inviter,
      team: team,
    )
  end

  test "belongs_to save to the database" do
    assert @invitation.valid?
    refute @invitation.new_record?

    assert @invitation.organization.present?
    assert @invitation.inviter.present?
    assert @invitation.invitee.present?
  end

  context ".find_by_token" do
    test "it returns the matching email invite" do
      invitation = create(:organization_invitation,
        organization: @org,
        inviter: @inviter,
        invitee: nil,
        email: "garrett@github.com",
        role: :direct_member,
      )

      assert_equal invitation, OrganizationInvitation.find_by_token(invitation.token)
    end
  end

  context "team_invitations" do
    test "save to the database" do
      assert_equal [@team_invitation], @invitation.team_invitations.reload.to_a
    end
  end

  context "teams" do
    test "preserves the invitation if the last team is destroyed" do
      org     = @invitation.organization
      invitee = @invitation.invitee

      @invitation.teams.each(&:destroy)

      refute_nil org.pending_invitation_for(invitee)
    end
  end

  context "invitee" do
    test "destroys the invitation when destroyed" do
      id = @invitation.id
      refute_nil OrganizationInvitation.find_by(id: id)

      @invitation.invitee.destroy

      assert_nil OrganizationInvitation.find_by(id: id)
    end
  end

  context "organization" do
    test "destroys the invitation when destroyed" do
      id = @invitation.id
      refute_nil OrganizationInvitation.find_by(id: id)

      @invitation.organization.destroy

      assert_nil OrganizationInvitation.find_by(id: id)
    end
  end

  test "pending scope" do
    accepted_invitation = create :organization_invitation
    accepted_invitation.accept
    cancelled_invitation = create :organization_invitation
    cancelled_invitation.cancel(actor: @inviter)

    assert_same_elements [@invitation, accepted_invitation, cancelled_invitation], OrganizationInvitation.all
    assert_same_elements [@invitation], OrganizationInvitation.pending
  end

  context "pending?" do
    test "is false when invitation is accepted" do
      assert_predicate @invitation, :pending?

      @invitation.accept

      refute_predicate @invitation, :pending?
    end

    test "is false when invitation is cancelled" do
      assert_predicate @invitation, :pending?

      @invitation.cancel(actor: @inviter)

      refute_predicate @invitation, :pending?
    end

    test "is true when invitation is not accepted or cancelled" do
      refute_predicate @invitation, :accepted?
      refute_predicate @invitation, :cancelled?
      assert_predicate @invitation, :pending?
    end
  end
end

class OrganizationInvitationwithInviteeOrNormalizedEmailTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization)
    @inviter = @org.admins.last
    @invitee = create(:user)
    @invitee.emails.each(&:verify!)
  end

  test "returns invitations for an invitee" do
    @org.invite(@invitee, inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(invitee: @invitee)
    assert_equal 1, invitations.size
    assert_includes invitations.map(&:invitee), @invitee
  end

  test "returns invitations for an email address" do
    @org.invite(nil, email: "email@example.com", inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(emails: "email@example.com")
    assert_equal 1, invitations.size
    assert_includes invitations.map(&:email), "email@example.com"
  end

  test "returns invitations for the email address of an invitee" do
    @org.invite(nil, email: @invitee.email, inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(emails: @invitee.email)
    assert_equal 1, invitations.size
    assert_equal invitations.first.email, @invitee.email
  end

  test "returns invitations for arbitrary email addresses or verified invitee email addresses" do
    @org.invite(nil, email: "email@example.com", inviter: @inviter)
    @org.invite(nil, email: "bob@example.com", inviter: @inviter)
    @invitee.emails.first.update_attribute(:state, "verified")
    @org.invite(nil, email: @invitee.email, inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(invitee: @invitee, emails: "email@example.com")
    assert_equal 2, invitations.size
    assert_equal invitations.first.email, @invitee.email
    assert_equal invitations.second.email, "email@example.com"
  end

  test "does not return invitations for other invitees" do
    @org.invite(nil, email: @invitee.email, inviter: @inviter)
    @org.invite(create(:user), inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(emails: @invitee.email)
    assert_equal 1, invitations.size
    assert_equal invitations.first.email, @invitee.email
  end

  test "considers multiple emails" do
    @org.invite(nil, email: "email@example.com", inviter: @inviter)

    invitations = @org.pending_invitations.with_invitee_or_normalized_email(emails: ["otheremail@example.com", "email@example.com"])
    assert_equal 1, invitations.size
    assert_equal invitations.first.email, "email@example.com"
  end
end

class OrganizationInvitationOptOutTest < GitHub::TestCase
  fixtures do
    @org     = create :organization
    @inviter = @org.admins.last
    @invitee = create(:user, email: "same_deobfuscated_email@gmail.com") # @invitee.emails[0].email MUST == @invitee.emails[0].deobfuscated_email
    @invitee.emails.each(&:verify!)
  end

  test "opts an email address out of receiving invitations" do
    invitation = @org.invite(nil, email: "email@example.com", inviter: @inviter, role: :direct_member)

    assert_difference("OrganizationInvitation::OptOut.count", 1) do
      invitation.opt_out(actor: User.ghost)
    end

    assert OrganizationInvitation::OptOut.opted_out?(org: @org, email: invitation.email), "email@example.com should be opted-out"
  end

  test "opts a user out of receiving invitations" do
    invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)

    assert_difference("OrganizationInvitation::OptOut.count", 1) do
      invitation.opt_out(actor: @invitee)
    end

    assert OrganizationInvitation::OptOut.opted_out?(org: @org, email: @invitee.email), "#{@invitee} should be opted-out"
  end

  test "opts out all verified user emails from receiving invitations" do
    @invitee.add_email("email_2@example.com")
    @invitee.add_email("email_3@example.com")
    @invitee.emails.each(&:verify!)
    invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)

    assert_difference("OrganizationInvitation::OptOut.count", 3) do
      invitation.opt_out(actor: @invitee)
    end

    @invitee.emails.map(&:deobfuscated_email).each do |email|
      assert OrganizationInvitation::OptOut.opted_out?(org: @org, email: email), "#{email} should be opted-out"
    end
  end

  test "cancels pending invitations to org when the user opts out" do
    invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)
    refute_predicate invitation, :cancelled?
    invitation.opt_out(actor: @invitee)
    assert_predicate invitation, :cancelled?
  end

  test "instruments the expected payload" do
    events     = subscribe("org.opt_out_invitation")
    invitation = @org.invite(nil, inviter: @inviter, email: "email@example.com")
    invitation.opt_out(actor: User.ghost)

    expected_payload = {
      actor: User.ghost.login,
      actor_id: User.ghost.id,
      email: invitation.email,
      invitee_email: invitation.email,
      org: @org.login,
      org_id: @org.id,
      invitation_id: invitation.id,
      role: "direct_member",
    }

    refute_nil event = events.pop
    assert_equal "org.opt_out_invitation", event.name
    assert_equal expected_payload, event.payload
  end
end

class OrganizationInvitationValidationsTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization)
    @inviter = @org.admins.last
    @invitee = create(:user)
    @invitee.emails.each(&:verify!)
  end

  test "can be valid" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      invitee: @invitee,
      role: :direct_member,
    )
    assert invitation.valid?, "should be valid"
  end

  test "requires an org" do
    invitation = OrganizationInvitation.new(
      inviter: @inviter,
      invitee: @invitee,
      role: :direct_member,
    )

    refute invitation.valid?, "should require an org"
  end

  test "requires an inviter" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      invitee: @invitee,
      role: :direct_member,
    )

    refute invitation.valid?, "should require an inviter"
  end

  test "email can't be more than 100 characters" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      email: "garrett@#{"a" * 100}.com",
      role: :direct_member,
    )

    refute invitation.valid?, "email not valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  test "email can't be more less than 3 characters" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      email: "aa",
      role: :direct_member,
    )

    refute invitation.valid?, "email not valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  test "email can't include a mailto: prefix" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      email: "mailto:mtodd@github.com",
      role: :direct_member,
    )

    refute_predicate invitation, :valid?, "email should not be valid"
    assert invitation.errors[:email].any?, "should have email error"
  end

  if GitHub.spamminess_check_enabled?
    test "organization can't be spammy" do
      @org.spammy = true
      @org.save
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
        role: :direct_member,
      )
      refute_predicate invitation, :valid?
      assert invitation.errors[:base].any?
    end
  end

  test "requires either an invitee or email" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      role: :direct_member,
    )

    refute invitation.valid?, "should require an invitee"
  end

  test "requires no invitee if email present" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      email: "garrett@github.com",
      role: :direct_member,
    )

    assert invitation.valid?, "should not require an invitee"
  end

  test "requires no email if invitee present" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      invitee: @invitee,
      role: :direct_member,
    )

    assert invitation.valid?, "should not require an email"
  end

  test "can't have both email and invitee" do
    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      invitee: @invitee,
      email: "garrett@github.com",
      role: :direct_member,
    )

    refute invitation.valid?, "should not have email and invitee"
  end

  test "invitee must not be blocking inviter" do
    blocker = create(:user)
    blocker.block(@inviter)

    invitation = OrganizationInvitation.new(
      organization: @org,
      inviter: @inviter,
      invitee: blocker,
      role: :direct_member,
    )

    refute invitation.valid?, "should not allow inviting a blocker"
  end

  context "opt out" do
    test "is invalid when an email is opted out of the organization" do

      invitation = create(:organization_invitation, :email, {
        organization: @org,
        inviter: @inviter,
        email: "optedout@example.com",
      })

      invitation.opt_out(actor: @org.admin)

      refute_predicate invitation, :valid?, "should not be valid when email is opted out"
      assert invitation.errors[:opt_out].any?, "should have an opt out error"
    end

    test "is invalid when an invitee is opted out of the organization" do

      invitation = create(:organization_invitation, {
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      })

      invitation.opt_out(actor: @org.admin)

      refute_predicate invitation, :valid?, "should not be valid when email is opted out"
      assert invitation.errors[:opt_out].any?, "should have an opt out error"
    end
  end

  context "requires role" do
    test "to be one of the valid symbols" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      )

      invitation.role = ""
      refute invitation.valid?, "should require a role"

      invitation.role = :direct_member
      assert invitation.valid?, "should work for the :direct_member role"

      invitation.role = :admin
      assert invitation.valid?, "should work for the :admin role"

      invitation.role = :reinstate
      assert invitation.valid?, "should work for the :reinstate role"
    end
  end
end

class OrganizationInvitationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @org     = create(:organization)
    @owner   = @org.admins.last
    @inviter = @owner
    @invitee = create(:user)
    @verified_email = "verified_email@example.com"
    @invitee.add_email(@verified_email)
    @invitee.emails.each(&:verify!)
    @unverified_email = "unverified_email@example.com"
  end

  context "purgeable scope" do
    test "returns failed and cancelled invitations" do
      failed = create :organization_invitation, :failed
      assert_predicate failed, :failed?
      cancelled = create :organization_invitation, organization: @org
      cancelled.cancel(actor: @inviter)
      assert_predicate cancelled, :cancelled?

      assert_same_elements \
        [failed, cancelled],
        OrganizationInvitation.purgeable
    end
  end

  context "create" do
    include HydroTestHelpers

    test "instruments the expected payload" do
      events     = subscribe("org.invite_member")
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: @invitee.login,
        user_id: @invitee.id,
        org: @org.login,
        org_id: @org.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
        role: "direct_member",
      }

      refute_nil event = events.pop
      assert_equal "org.invite_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments the expected payload with email invitation" do
      events     = subscribe("org.invite_member")
      invitation = @org.invite(email: "garrett@github.com", inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.cancel(actor: @inviter)

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: "garrett@github.com",
        invitee_email: "garrett@github.com",
        org: @org.login,
        org_id: @org.id,
        invitation_id: invitation.id,
        role: "direct_member",
      }

      refute_nil event = events.pop
      assert_equal "org.invite_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "publishes the OrganizationInviteMember hydro event", skip_enterprise: true do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        create(:profile, user: @org, name: "High velocity business")
        invitation = @org.invite(
          email: "user@github.com",
          inviter: @inviter,
          teams: [create(:team, organization: @org)],
        )
        invitation.cancel(actor: @inviter)

        message = {
          request_context: nil,
          organization: Hydro::EntitySerializer.organization(@org),
          actor: Hydro::EntitySerializer.user(@inviter),
          email: invitation.email,
          user: Hydro::EntitySerializer.user(invitation.invitee),
          invitation: Hydro::EntitySerializer.invitation(invitation),
          organization_profile: Hydro::EntitySerializer.profile(@org.profile),
        }

        T.unsafe(self).assert_hydro_published(message, schema: "github.v1.OrganizationInviteMember")
        T.unsafe(self).assert_hydro_messages count: 1, schema: "github.v1.OrganizationInviteMember"
      end
    end
  end

  context "destroy" do
    test "removes OrganizationInvitation" do
      invitation = create :organization_invitation, invitee: @invitee, organization: @org, inviter: @inviter

      assert_difference "OrganizationInvitation.count", -1 do
        invitation.destroy!
      end
    end

    test "works even if the organization no longer exists" do
      invitation = create :organization_invitation, invitee: @invitee, organization: @org, inviter: @inviter

      # Mock the situation where the organization no longer exists
      invitation.update_column :organization_id, 0
      refute invitation.organization.present?

      assert_difference "OrganizationInvitation.count", -1 do
        invitation.destroy!
      end
    end
  end

  context "accept" do
    test "adds the invitee to the org and all specified teams" do
      teams      = Array.new(2) { create(:team, organization: @org) }
      invitation = @org.invite(@invitee, inviter: @inviter, teams: teams)

      # Make sure the invitee starts out as not a member of the org or teams.
      refute @org.direct_or_team_member?(@invitee)
      teams.each { |team| refute team.member?(@invitee) }

      result = invitation.accept

      assert_predicate result, :success?
      assert invitation.accepted?
      assert @org.direct_member?(@invitee)
      teams.each { |team| assert team.member?(@invitee) }
    end

    test "adds the invitee as an org member when the :direct_member role is specified" do
      invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)

      # Make sure the invitee starts out as not a member of the org.
      refute @org.direct_or_team_member?(@invitee)

      invitation.accept

      assert invitation.accepted?
      assert @org.direct_member?(@invitee)
      refute @org.adminable_by?(@invitee)
    end

    test "adds the invitee as an org owner when the :admin role is specified" do
      invitation = @org.invite(@invitee, inviter: @inviter, role: :admin)

      # Make sure the invitee starts out as not a member of the org.
      refute @org.direct_or_team_member?(@invitee)

      invitation.accept

      assert invitation.accepted?
      assert @org.direct_member?(@invitee)
      assert @org.adminable_by?(@invitee)
    end

    test "adds the invitee as a team maintainer when specified" do
      invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)

      member_team = create(:team, organization: @org, name: "member-team")
      invitation.add_team(member_team, inviter: @inviter, role: :member)

      maintainer_team = create(:team, organization: @org, name: "maintainer-team")
      invitation.add_team(maintainer_team, inviter: @inviter, role: :maintainer)

      invitation.accept

      assert member_team.member?(@invitee)
      refute member_team.maintainer?(@invitee)
      assert maintainer_team.member?(@invitee)
      assert maintainer_team.maintainer?(@invitee)
    end

    test "queues RestoreOrganizationUser job when role is :reinstate" do
      restorable_org_user = create(:restorable_organization_user, :complete)
      org = restorable_org_user.organization
      invitee = restorable_org_user.user
      invitation = org.invite(invitee, inviter: org.admin, role: :reinstate)

      assert_enqueued_with job: RestoreOrganizationUserJob, queue: "restore_organization_user" do
        invitation.accept
        assert invitation.accepted?, "Organization invite was accepted"
      end
    end

    test "removes OrganizationUser restorable if role is not :reinstate and restorable exists" do
      restorable_org_user = create(:restorable_organization_user, :complete)
      org = restorable_org_user.organization
      invitee = restorable_org_user.user
      invitation = org.invite(invitee, inviter: org.admin, role: :direct_member)

      invitation.accept

      assert invitation.accepted?, "Organization invite was accepted"
      restorable = Restorable::OrganizationUser.restorable(org, invitee)
      refute restorable.restorable?
    end

    test "queues Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob job when org business has volume_license_enabled", skip_enterprise: true do
      business = create(:business, :volume_licensed, organizations: [@org])
      @org.reload

      invitation = @org.invite(@invitee, inviter: @inviter, role: :direct_member)

      # Make sure the invitee starts out as not a member of the org.
      refute @org.direct_or_team_member?(@invitee)

      assert_enqueued_with job: Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob, queue: "licensing" do
        invitation.accept
        assert invitation.accepted?, "Organization invite was accepted"
      end
    end

    test "adds the invitee as a direct member when role is :reinstate but the associated RestoreOrganizationUser can't be found" do
      org = create(:organization)
      invitee = create(:user)

      # Make sure the invitee starts out as not a member of the org.
      refute org.direct_or_team_member?(invitee)

      invitation = org.invite(invitee, inviter: org.admin, role: :reinstate)

      invitation.accept

      assert invitation.accepted?, "Organization invite was accepted"
      assert invitation.accepted?
      assert org.direct_member?(invitee)
      refute org.adminable_by?(invitee)
    end

    test "does not work if organization is trade controls restricted" do
      org = create(:organization)
      invitee = create(:user)
      invitation = org.invite(invitee, inviter: org.admin)

      org.trade_controls_restriction.full!

      result = invitation.accept
      assert result.error?
      assert_match  "Due to U.S. trade controls law restrictions, we are unable to provide this feature.", result.error
    end

    test "does not work if the acceptor is not the invitee" do
      rando = create(:user)
      invitation = @org.invite(@invitee, inviter: @org.admin)

      result = invitation.accept(acceptor: rando)
      assert result.error?
      assert_match  "Invitee must accept invitation", result.error
    end

    test "links ExternalIdentity to the verified invited email's user", skip_enterprise: true do
      provider = create(:organization_saml_provider)
      org = provider.organization
      user = create(:user)

      assert_equal 0, org.saml_provider.external_identities.count
      assert_equal 0, user.external_identities.count
      assert_equal 1, org.members.count

      scim_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
      scim_user_data.append "userName", user.email
      scim_user_data.append "emails", user.email

      result = Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(
        organization_id: org.id,
        user_data: scim_user_data,
        inviter_id: org.members.first.id,
        mapper: Platform::Provisioning::ScimMapper)

      assert_equal 1, org.saml_provider.external_identities.count
      assert_equal 0, user.external_identities.count
      assert_equal 1, org.pending_invitations.count

      invitation = org.pending_invitation_for(email: user.email)
      # email to which invite was addressed needs to be verified before invite can be accepted
      user.emails.first.verify!
      invitation.accept(acceptor: user)

      assert_equal 1, org.saml_provider.external_identities.count
      assert_equal 1, user.external_identities.count
      assert_equal 0, org.pending_invitations.count
      assert_equal user.external_identities.first, result.external_identity
    end

    if GitHub.billing_enabled?
      test "adds the invitee as a billing manager, when the :billing_manager role is specified" do
        invitation = @org.invite(@invitee, inviter: @inviter, role: :billing_manager)

        invitation.accept

        assert invitation.accepted?
        assert @org.billing_manager?(@invitee)
      end

      test "adds the invitee as a billing manager, when the :billing_manager role is specified, to a legacy org" do
        invitation = @org.invite(@invitee, inviter: @inviter, role: :billing_manager)

        invitation.accept

        assert invitation.accepted?
        assert @org.billing_manager?(@invitee)
      end

      test "correctly intruments accepting billing manager invites to verified email addresses" do
        @invitee.add_email("invitee@example.com").verify!
        invite = @org.invite(email: "invitee@example.com", inviter: @inviter, role: :billing_manager)

        events = subscribe "org.add_billing_manager"
        invite.accept(acceptor: @invitee)

        expected_payload = {
          actor: @inviter.login,
          actor_id: @inviter.id,
          org: @org.login,
          org_id: @org.id,
          user: @invitee.login,
          user_id: @invitee.id,
          invitation_email: "invitee@example.com",
        }

        assert event = events.pop, "expected an event"
        assert_equal expected_payload, event.payload
      end
    end

    test "can't be accepted twice" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.accept

      result = invitation.accept
      assert result.error?
      assert_match "This invitation has already been accepted", result.error
    end

    test "cleans up if there's an exception while adding to a team" do
      teams      = Array.new(2) { create(:team, organization: @org) }
      invitation = @org.invite(@invitee, inviter: @inviter, teams: teams)

      # Make OrganizationInvitation#accept error in the middle of the call.
      Team.any_instance.stubs(:add_member).raises(StandardError.new)

      assert_raises(StandardError) { invitation.accept }
      refute invitation.accepted?
      refute @org.direct_or_team_member?(@invitee)
      teams.each { |team| refute team.member?(@invitee) }
    end

    test "cleans up if it can't add the user to a team" do
      teams      = Array.new(2) { create(:team, organization: @org) }
      invitation = @org.invite(@invitee, inviter: @inviter, teams: teams)

      # Make OrganizationInvitation#accept error in the middle of the call.
      Team.any_instance.stubs(:add_member).returns(Team::AddMemberStatus::NO_SEAT)

      result = invitation.accept
      assert result.error?
      assert_match "There are no available seats in this organization", result.error

      refute invitation.accepted?
      refute @org.direct_or_team_member?(@invitee)
      teams.each { |team| refute team.member?(@invitee) }
    end

    test "doesn't add member to team if user does not meet 2fa requirement" do
      org_admin = @org.admins.first
      @org.enable_two_factor_requirement(actor: org_admin)

      team = create(:team, organization: @org)

      user = create(:user)
      invite = @org.invite(user, inviter: org_admin, teams: Array(team))

      refute @org.two_factor_requirement_met_by?(user), "#{user} should not meet 2fa requirement"

      result = invite.accept
      refute_predicate result, :success?
      assert_equal :no_2fa, result.status
      refute invite.accepted?
      refute_includes @org.members, user
      refute team.member?(user)
    end

    test "does add org member if they do meet 2fa requirement" do
      invitee = create(:two_factor_credential_user)
      two_factor_org = create(:organization, admin: @inviter)
      two_factor_org.enable_two_factor_requirement(actor: @inviter)
      invite = two_factor_org.invite(invitee, inviter: @inviter)
      status = invite.accept(acceptor: invitee)
      assert_predicate status, :success?
      assert two_factor_org.reload.member?(invitee)
    end

    test "does not add org member if they do not meet 2fa requirement" do
      invitee = create(:two_factor_credential_user, login: "foo")
      two_factor_org = create(:two_factor_credential_organization)
      inviter = two_factor_org.admins.first
      two_factor_org.reload
      assert_predicate two_factor_org, :two_factor_requirement_enabled?
      assert_predicate invitee, :two_factor_authentication_enabled?

      invite = two_factor_org.invite(invitee, inviter: inviter)
      invitee.two_factor_credential.destroy
      invitee.reload
      refute_predicate invitee, :two_factor_authentication_enabled?

      result = invite.accept(acceptor: invitee)
      refute_predicate result, :success?
      assert_equal :no_2fa, result.status
      refute two_factor_org.reload.member?(invitee)
      assert_nil invite.accepted_at
    end

    test "allow email-based invitation to be accepted when 2FA is required by the organization, but the user doesn't have it set up", skip_enterprise: true do
      business = create(:business)
      business.add_organization(@org)
      @org.reload # ensure organization knows about business

      invite = @org.invite(email: @invitee.email, inviter: @inviter)
      # Match what happens in the signup controller when 2FA requirements aren't met
      # https://github.com/github/github/blob/55bf4c723a694f45fa62d8c0cfeb87453ae81193/app/controllers/signup_controller.rb#L270
      invite.update_attribute(:invitee_id, @invitee.id)

      invite.accept(acceptor: @invitee)

      assert_predicate invite.reload, :accepted?

      assert @org.direct_or_team_member?(@invitee)
    end

    test "doesn't add member to team if user does not meet the SAML SSO requirement" do
      saml_identity = create :external_identity
      saml_org = saml_identity.target
      saml_org.saml_provider.enforce!

      org_admin = saml_org.admins.first
      team = create :team, organization: saml_org
      user = create(:user)
      invite = saml_org.invite(user, inviter: org_admin, teams: Array(team))

      refute saml_org.saml_sso_requirement_met_by?(user), "#{user} should not meet SAML SSO requirement"

      result = invite.accept
      assert result.error?
      assert_match "You do not satisfy the SAML SSO requirements of this organization", result.error

      refute invite.accepted?
      refute_includes saml_org.members, user
      refute team.member?(user), "#{user} should not be a member of team #{team}"
    end

    test "doesn't add member to team which is externally managed", team_synchronization_available: true do
      owner = create(:user)
      saml_org = create(:business_plus_org, login: "saml-org", admin: owner)
      saml_provider = create(:organization_saml_provider, organization: saml_org, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")

      # Setup multiple teams for the invitation, only one will be externally managed
      team1 = create(:team, organization: saml_org)
      team2 = create(:team, organization: saml_org)
      invitation = saml_org.invite(@invitee, inviter: owner, teams: [team1, team2])

      # Invitation is created, now lets enable team_sync for the org
      # and externally manage the team
      create :team_sync_tenant, organization: saml_org

      team1.group_mappings.create!(
        group_id: "2f541442-f02c-ea34-a6cb-fecc0ce0dcff",
        group_name: "cats",
        group_description: "Kittens",
      )

      invitation.accept

      assert invitation.accepted?
      assert_includes saml_org.members, @invitee
      # Only the externally managed team should be ignored
      refute team1.member?(@invitee), "#{@invitee} should not be a member of externally managed team #{team1}"
      assert team2.member?(@invitee), "#{@invitee} should be a member of externally managed team #{team2}"
    end

    test "adds a member when, excluding her invite, there are no seats left" do
      @org.update(plan: "business", seats: 2)
      teams      = Array.new(2) { create(:team, organization: @org) }
      invitation = @org.invite(@invitee, inviter: @inviter, teams: teams)

      assert @org.at_seat_limit?

      invitation.accept

      assert invitation.accepted?
      assert @org.direct_or_team_member?(@invitee)
      teams.each { |team| assert team.member?(@invitee) }
    end

    test "cancels a user invite that was created before an email invite that was sent to a verified email address" \
    "when accepting the email invite" do

      @invitee.add_email("octocat@example.com").verify!
      team = create(:team, organization: @org)
      user_invite  = @org.invite(@invitee, inviter: @inviter, teams: [team])
      email_invite = @org.invite(nil, email: "octocat@example.com", inviter: @inviter)
      other_user_invite = @org.invite(create(:user), inviter: @inviter)

      email_invite.accept(acceptor: @invitee)

      assert_predicate email_invite.reload, :accepted?
      refute_predicate other_user_invite.reload, :accepted?
      refute_predicate user_invite.reload, :accepted?
      assert_predicate user_invite, :cancelled?

      assert @org.direct_or_team_member?(@invitee)
      assert team.member?(@invitee)
    end

    test "auto cancels multiple duplicate email invites when accepting" \
    "an email invite to a verified email, but only adds teams from invites to verified emails" do
      @invitee.add_email("octocat@example.com").verify!
      @invitee.add_email("alice@example.com")
      @invitee.add_email("sombra@example.com")

      team = create(:team, organization: @org)
      team2 = create(:team, organization: @org)
      team3 = create(:team, organization: @org)

      user_invite  = @org.invite(@invitee, inviter: @inviter, teams: [team])
      email_invite = @org.invite(nil, email: "octocat@example.com", inviter: @inviter)
      second_email_invite = @org.invite(nil, email: "alice@example.com", inviter: @inviter, teams: [team2])
      third_email_invite = @org.invite(nil, email: "sombra@example.com", inviter: @inviter, teams: [team3])
      other_email_invite = @org.invite(nil, email: "bob@example.com", inviter: @inviter)

      email_invite.accept(acceptor: @invitee)

      assert_predicate email_invite.reload, :accepted?
      assert_predicate user_invite.reload, :cancelled?
      refute_predicate user_invite.reload, :accepted?
      refute_predicate other_email_invite.reload, :accepted?
      [second_email_invite, third_email_invite].each do |invite|
        invite.reload

        refute_predicate invite, :cancelled?
        refute_predicate invite, :accepted?
      end

      assert @org.direct_or_team_member?(@invitee)
      assert team.member?(@invitee)
      refute team2.member?(@invitee)
      refute team3.member?(@invitee)
    end

    test "Team invitations for duplicate email and user invites are all accepted when email invite is accepted" do
      organization_invitation_one = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      organization_invitation_two = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      organization_invitation_three = create(
        :organization_invitation,
        invitee: @invitee,
        organization: @org,
        inviter: @inviter,
      )

      team_invitation_one = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_one,
      )
      team_invitation_two = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_two,
      )
      team_invitation_three = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_three,
      )

      organization_invitation_one.accept(acceptor: @invitee)
      assert team_invitation_one.team.member?(@invitee)
      assert team_invitation_two.team.member?(@invitee)
      assert team_invitation_three.team.member?(@invitee)
    end

    test "Team invitations for duplicate user and email invites are all accepted when user invite is accepted" do
      organization_invitation_one = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      organization_invitation_two = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      organization_invitation_three = create(
        :organization_invitation,
        invitee: @invitee,
        organization: @org,
        inviter: @inviter,
      )

      team_invitation_one = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_one,
      )
      team_invitation_two = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_two,
      )
      team_invitation_three = create(
        :team_invitation,
        team: create(:team, organization: @org),
        organization_invitation: organization_invitation_three,
      )

      organization_invitation_three.accept(acceptor: @invitee)
      assert team_invitation_one.team.member?(@invitee)
      assert team_invitation_two.team.member?(@invitee)
      assert team_invitation_three.team.member?(@invitee)
    end

    test "Duplicate email and user invites are all cancelled when email invite is accepted" do
      invite_one = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      invite_two = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      invite_three = create(
        :organization_invitation,
        invitee: @invitee,
        organization: @org,
        inviter: @inviter,
      )

      invite_one.accept(acceptor: @invitee)
      assert_predicate invite_one.reload, :accepted?
      refute_predicate invite_two.reload, :accepted?
      assert_predicate invite_two.reload, :cancelled?
      refute_predicate invite_three.reload, :accepted?
      assert_predicate invite_three.reload, :cancelled?
    end

    test "Duplicate email and user invites are all cancelled when user invite is accepted" do
      invite_one = create(
        :organization_invitation,
        :email,
        email: @invitee.email,
        organization: @org,
        inviter: @inviter,
      )
      invite_two = create(
        :organization_invitation,
        invitee: @invitee,
        organization: @org,
        inviter: @inviter,
      )
      invite_three = create(
        :organization_invitation,
        invitee: @invitee,
        organization: @org,
        inviter: @inviter,
      )

      invite_two.accept
      assert_predicate invite_two.reload, :accepted?
      refute_predicate invite_one.reload, :accepted?
      assert_predicate invite_one.reload, :cancelled?
      refute_predicate invite_three.reload, :accepted?
      assert_predicate invite_three.reload, :cancelled?
    end

    test "handles invites that have been updated to reflect a user signing up but not yet accepting due to 2fa" do
      invite = @org.invite(email: @invitee.email, inviter: @inviter)
      invite.update_attribute(:invitee_id, @invitee.id)

      invite.accept(acceptor: @invitee)

      assert_predicate invite.reload, :accepted?

      assert @org.direct_or_team_member?(@invitee)
    end

    test "returns blocked error status if acceptor is blocked by org" do
      blocked_user = create(:user)
      @org.block(blocked_user)
      assert @org.blocking?(blocked_user)

      invite = create(:organization_invitation, :email, organization: @org)
      result = invite.accept(acceptor: blocked_user)

      refute_predicate result, :success?
      assert_equal :blocked, result.status
    end

    test "returns expired error status if invite is expired" do
      invite = T.let(nil, T.nilable(OrganizationInvitation))

      Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        invite = @org.invite(@invitee, inviter: @inviter)
      end

      result = T.must(invite).accept(acceptor: @invitee)

      refute_predicate result, :success?
      assert_equal :expired, result.status
    end

    test "sets invite to expired if it has been longer than the expiry period" do
      invite = T.let(nil, T.nilable(OrganizationInvitation))

      Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        invite = @org.invite(@invitee, inviter: @inviter)
      end

      refute T.must(invite).failed_reason

      T.must(invite).accept(acceptor: @invitee)

      assert_equal "expired", T.must(invite).failed_reason
    end

    # see https://github.com/github/github/issues/142861 for context on this
    test "does not validate exclusivity of invitee_id and email during update" do
      invitation = OrganizationInvitation.create(
          organization: @org,
          inviter: @inviter,
          email: "garrett@github.com",
          role: :direct_member,
          )

      invitation.update(invitee_id: 1)

      assert_predicate invitation, :valid?
    end

    test "expired scope does not consider invites expired after expiration cutoff period" do
      # Having a cutoff date in the expired scope considerably reduces the cost of the query,
      # as an unbounded date query would consider all the matching records since the beginning of time.
      invite = T.let(nil, T.nilable(OrganizationInvitation))

      Timecop.travel((GitHub.invitation_expiry_cutoff + 1).days.ago) do
        invite = @org.invite(@invitee, inviter: @inviter)
      end

      # the invitation should be expired
      assert T.must(invite).invite_expired?

      # but it won't appear in the expired scope.
      assert_empty OrganizationInvitation.recently_expired
    end

    test "expired invites are not pending" do
      invite = T.let(nil, T.nilable(OrganizationInvitation))

      Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        invite = @org.invite(@invitee, inviter: @inviter)
      end

      refute T.must(invite).failed_reason

      T.must(invite).accept(acceptor: @invitee)

      assert_equal "expired", T.must(invite).failed_reason
      refute T.must(invite).pending?
    end

    test "does not work for email address invites when signed in to a user account that has neither added nor verified the email address to which the invite was sent" do
      email_invite = @org.invite(email: "not_added_not_verified_email@example.com", inviter: @owner)
      refute @invitee.emails.pluck(:email).include?(email_invite.email)
      refute @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute @org.direct_or_team_member?(@invitee)

      email_invite.accept(acceptor: @invitee)

      refute_predicate email_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
    end

    test "does not work for email address invites to business when signed in to a user account that has neither added nor verified the email address to which the invite was sent" do
      business = create :business, organizations: [@org]
      @org.reload
      email_invite = @org.invite(email: "not_added_not_verified_email@example.com", inviter: @owner)
      refute @invitee.emails.pluck(:email).include?(email_invite.email)
      refute @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute @org.direct_or_team_member?(@invitee)

      email_invite.accept(acceptor: @invitee)

      refute_predicate email_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
    end

    test "does not work for email address invites when signed in to a user account that has added but not verified the email address to which the invite was sent" do
      @invitee.add_email(@unverified_email)
      email_invite = @org.invite(email: @unverified_email, inviter: @owner)
      assert @invitee.emails.pluck(:email).include?(email_invite.email)
      refute @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute @org.direct_or_team_member?(@invitee)

      email_invite.accept(acceptor: @invitee)

      refute_predicate email_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
    end

    test "does not work for email address invites to business when signed in to a user account that has added but not verified the email address to which the invite was sent" do
      business = create :business, organizations: [@org]
      @org.reload
      @invitee.add_email(@unverified_email)
      email_invite = @org.invite(email: @unverified_email, inviter: @owner)
      assert @invitee.emails.pluck(:email).include?(email_invite.email)
      refute @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute @org.direct_or_team_member?(@invitee)

      email_invite.accept(acceptor: @invitee)

      refute_predicate email_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
    end

    test "works for email address invites when signed in to a user account that has added and verified the email address to which the invite was sent" do
      email_invite = @org.invite(email: @verified_email, inviter: @owner)
      assert @invitee.emails.pluck(:email).include?(email_invite.email)
      assert @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute @org.direct_or_team_member?(@invitee)

      email_invite.accept(acceptor: @invitee)

      assert_predicate email_invite.reload, :accepted?
      assert @org.direct_or_team_member?(@invitee)
    end

    test "doesn't work for email address invites when signed in to a spammy user account that has added and verified the email address to which the invite was sent" do
      @invitee.mark_as_spammy
      email_invite = @org.invite(email: @verified_email, inviter: @owner)
      assert @invitee.emails.pluck(:email).include?(email_invite.email)
      assert @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      assert @invitee.spammy?
      refute @org.direct_or_team_member?(@invitee)

      result = email_invite.accept(acceptor: @invitee)

      refute result.success?
      refute_predicate email_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
      assert_equal result.status, :spammy_invitee
    end

    test "doesn't work for normal org invites sent to a spammy user account" do
      @invitee.mark_as_spammy
      org_invite = @org.invite(@invitee, inviter: @owner)
      assert @invitee.spammy?
      refute @org.direct_or_team_member?(@invitee)

      result = org_invite.accept(acceptor: @invitee)

      refute result.success?
      refute_predicate org_invite.reload, :accepted?
      refute @org.direct_or_team_member?(@invitee)
      assert_equal result.status, :spammy_invitee
    end

    unless GitHub.bypass_org_invites_enabled?
      test "instruments org.add_member audit log event with correct attribution" do
        @invite = @org.invite(@invitee, inviter: @inviter)

        events = subscribe "org.add_member"
        @invite.accept

        expected_payload = {
          actor: @inviter.login,
          actor_id: @inviter.id,
          invitation_id: @invite.id,
          org: @org.login,
          org_id: @org.id,
          permission: :read,
          user: @invitee.login,
          user_id: @invitee.id,
        }

        assert event = events.pop, "expected an event"
        assert_equal event.payload, expected_payload
      end

      test "instruments org.add_member audit log event with info on what verified email address was invited" do
        @invitee.add_email("invitee@example.com").verify!
        invite = @org.invite(email: "invitee@example.com", inviter: @inviter)

        events = subscribe "org.add_member"
        invite.accept(acceptor: @invitee)

        expected_payload = {
          actor: @inviter.login,
          actor_id: @inviter.id,
          invitation_id: invite.id,
          org: @org.login,
          org_id: @org.id,
          permission: :read,
          user: @invitee.login,
          user_id: @invitee.id,
          invitation_email: "invitee@example.com",
        }

        assert event = events.pop, "expected an event"
        assert_equal expected_payload, event.payload
      end

      test "instruments team.add_member audit log event with correct attribution" do
        org_admin = create(:user)
        team = create(:team, organization: @org)
        @org.add_member(org_admin)
        @invite = @org.invite(@invitee, inviter: @inviter)
        @invite.add_team(team, inviter: org_admin)

        events = subscribe "team.add_member"

        @invite.accept

        expected_payload = {
          actor: org_admin.login,
          actor_id: org_admin.id,
          team: team.combined_slug,
          team_id: team.id,
          org: @org.login,
          org_id: @org.id,
          user: @invitee.login,
          user_id: @invitee.id,
          note: "Team #{team.combined_slug}",
          ldap_mapped: false,
        }

        assert event = events.pop, "expected an event"
        assert_equal event.payload, expected_payload
      end
    end

    test "instruments accepting invite" do
      teams      = Array.new(2) { create(:team, organization: @org) }
      invitation = @org.invite(@invitee, inviter: @inviter, teams: teams)
      GlobalInstrumenter.expects(:instrument).with(any_parameters).at_least(0)
      GlobalInstrumenter.expects(:instrument).with("org.member_invite_accepted", has_entries(invitation: invitation)).once

      # Make sure the invitee starts out as not a member of the org or teams.
      refute @org.direct_or_team_member?(@invitee)
      teams.each { |team| refute team.member?(@invitee) }

      result = invitation.accept

      assert_predicate result, :success?
      assert invitation.accepted?
    end
  end

  context "accepted?" do
    test "is false before the invitation has been accepted" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])

      refute invitation.accepted?
    end

    test "is true after the invitation has been accepted" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.accept

      assert invitation.accepted?
    end
  end

  context "add_team" do
    test "adds the specified team to the invitation" do
      team1      = create(:team, organization: @org)
      team2      = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team1])

      assert_same_elements [team1], invitation.teams

      invitation.add_team(team2, inviter: @inviter)

      assert_same_elements [team1, team2], invitation.teams
    end

    test "sets the team invitation's role to :member by default" do
      team       = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.add_team(team, inviter: @inviter)

      assert_predicate invitation.team_invitation_for(team), :member?
    end

    test "can set the team invitation's role to :maintainer" do
      team       = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.add_team(team, inviter: @inviter, role: :maintainer)

      assert_predicate invitation.team_invitation_for(team), :maintainer?
    end

    test "can change a team invitation's role from :member to :maintainer" do
      team       = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.add_team(team, inviter: @inviter, role: :member)
      invitation.add_team(team, inviter: @inviter, role: :maintainer)

      assert_predicate invitation.team_invitation_for(team), :maintainer?
    end

    test "fails silently if the specified team is already on the invitation" do
      team1      = create(:team, organization: @org)
      team2      = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team1, team2])

      assert_same_elements [team1, team2], invitation.teams

      invitation.add_team(team2, inviter: @inviter)

      assert_same_elements [team1, team2], invitation.reload.teams
    end
  end

  context "includes_team?" do
    test "is true when the specified team is included in the invitation" do
      team = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team])

      assert invitation.includes_team?(team)
    end

    test "is false when the specified team isn't included in the invitation" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])

      refute invitation.includes_team?(create(:team, organization: @org))
    end
  end

  context "cancel" do
    include HydroTestHelpers

    test "soft-deletes the invitation when pending" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])

      Timecop.freeze(Time.zone.local(2016, 6, 4, 1, 0, 0)) do |time|
        assert_no_difference("OrganizationInvitation.count") do
          invitation.cancel(actor: @inviter)
        end

        assert_equal time, invitation.reload.cancelled_at
      end
    end

    test "raises an error and doesn't delete the invitation when accepted" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.accept

      assert_no_difference "OrganizationInvitation.count" do
        assert_raises OrganizationInvitation::AlreadyAcceptedError do
          invitation.cancel(actor: @inviter)
        end
      end
    end

    test "instruments the expected payload" do
      user = create(:user)
      events     = subscribe("org.cancel_invitation")
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.cancel(actor: user)

      event            = events.pop
      expected_payload = {
        actor: user.login,
        actor_id: user.id,
        user: @invitee.login,
        user_id: @invitee.id,
        org: @org.login,
        org_id: @org.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
        role: "direct_member",
      }

      refute_nil event
      assert_equal "org.cancel_invitation", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments the expected payload with email invitation" do
      events     = subscribe("org.cancel_invitation")
      invitation = @org.invite(email: "garrett@github.com", inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.cancel(actor: @inviter)

      event            = events.pop
      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: "garrett@github.com",
        invitee_email: "garrett@github.com",
        org: @org.login,
        org_id: @org.id,
        invitation_id: invitation.id,
        role: "direct_member",
      }

      refute_nil event
      assert_equal "org.cancel_invitation", event.name
      assert_equal expected_payload, event.payload
    end

    test "publishes the OrganizationCancelInvitation hydro event", skip_enterprise: true do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        create(:profile, user: @org, name: "High velocity business")
        invitation = @org.invite(
          email: "user@github.com",
          inviter: @inviter,
          teams: [create(:team, organization: @org)],
        )
        invitation.cancel(actor: @inviter)

        message = {
          request_context: nil,
          organization: Hydro::EntitySerializer.organization(@org),
          actor: Hydro::EntitySerializer.user(@inviter),
          email: invitation.email,
          user: Hydro::EntitySerializer.user(invitation.invitee),
          invitation: Hydro::EntitySerializer.invitation(invitation),
          organization_profile: Hydro::EntitySerializer.profile(@org.profile),
        }

        T.unsafe(self).assert_hydro_published(message, schema: "github.v1.OrganizationCancelInvitation")
        T.unsafe(self).assert_hydro_messages count: 1, schema: "github.v1.OrganizationCancelInvitation"
      end
    end

    if GitHub.spamminess_check_enabled?
      test "does not send a cancel email if inviter is spammy" do
        @inviter.mark_as_spammy
        assert @inviter.spammy?

        invitation = @org.invite(@invitee, inviter: @inviter)
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          invitation.cancel(actor: @inviter)
        end
      end
    end

    test "cancelling works if inviter has deleted their account" do
      inviter = create(:user)
      invitation = create(:organization_invitation, organization: @org, inviter: inviter, invitee: @invitee)
      # delete inviter's account
      inviter.destroy!

      assert_nil invitation.reload.inviter
      invitation.cancel(actor: @org.admins.first)
      assert_predicate invitation, :cancelled?
    end

    test "queues a job to send a status message to VSS", skip_enterprise: true do
      @org.business = create(:business, :volume_licensed)
      invitation = create(:organization_invitation,
                          organization: @org,
                          invitee: @invitee,
                          inviter: @inviter)
      create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: @invitee.email)
      create(:licensing_bundled_license_assignment, business_id: @org.business.id, email: @invitee.email)

      assert_enqueued_jobs 2, only: Licensing::SendVssStatusMessageJob do
        invitation.cancel(actor: @invitee)
      end
    end

    if GitHub.billing_enabled?
      test "does not send a cancel email for billing managers" do
        invitation = @org.invite(@invitee, inviter: @inviter, role: :billing_manager)
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          invitation.cancel(actor: @inviter)
        end
      end
    end
  end

  context "cancelable_by?" do
    test "true for an org owner" do
      invitation = @org.invite(@invitee, inviter: @owner, teams: [create(:team, organization: @org)])
      assert invitation.cancelable_by?(@owner)
    end

    test "true for an installation on the org with members write" do
      invitation = @org.invite(@invitee, inviter: @owner, teams: [create(:team, organization: @org)])
      installation = make_integration_installation(target: @org, permissions: { "members" => :write })

      assert invitation.cancelable_by?(installation.bot)
    end

    test "true for an org owner on an invitation with no teams" do
      invitation = @org.invite(@invitee, inviter: @owner, role: :direct_member)
      assert invitation.cancelable_by?(@owner)
    end

    test "true for the invitee" do
      invitation = @org.invite(@invitee, inviter: @owner, role: :direct_member)
      assert invitation.cancelable_by?(@invitee)
    end

    test "true for an email invite, if the canceler has verified the email address associated with the invite" do
      invitation = @org.invite(email: @verified_email, inviter: @owner)
      assert invitation.cancelable_by?(@invitee)
    end

    test "false for an email invite, if the canceler has not verified the email address associated with the invite" do
      invitation = @org.invite(email: @unverified_email, inviter: @owner)
      refute invitation.cancelable_by?(@invitee)
    end

    test "true if org belongs to a business and canceler is a business owner" do
      business = create(:business, organizations: [@org])
      invitation = @org.invite(@invitee, inviter: @owner, teams: [create(:team, organization: @org)])
      assert invitation.cancelable_by?(business.owners.first)
    end

    test "false for non org members" do
      invitation = @org.invite(@invitee, inviter: @owner, role: :direct_member)
      refute invitation.cancelable_by?(create(:user))
    end
  end

  context "remove_team" do
    test "removes the specified team from the invitation" do
      team1      = create(:team, organization: @org)
      team2      = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team1, team2])

      invitation.remove_team(team1)

      assert_equal [team2], invitation.reload.teams
    end

    test "does not cancel the invitation if the last team is removed and direct org membership is enabled" do
      team       = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team])
      invitation.remove_team(team)

      refute_nil @org.pending_invitation_for(@invitee)
    end

    test "fails silently if the specified team isn't on the invitation" do
      team1      = create(:team, organization: @org)
      team2      = create(:team, organization: @org)
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [team1])

      assert_equal [team1], invitation.teams

      invitation.remove_team(team2)

      assert_equal [team1], invitation.reload.teams
    end
  end

  context "role" do
    test "properly translates 1 to :direct_member" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      )
      invitation[:role] = 1

      assert_predicate invitation, :direct_member?
    end

    test "properly translates 2 to :admin" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      )
      invitation[:role] = 2

      assert_predicate invitation, :admin?
    end

    test "reinstate?" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
        role: :reinstate,
      )

      assert_predicate invitation, :reinstate?

      invitation.role = :admin
      invitation.save
      invitation.reload

      refute_predicate invitation, :reinstate?
    end
  end

  context "role=" do
    test "properly sets role to :direct_member" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      )
      invitation.role = :direct_member
      invitation.save
      invitation.reload

      assert_predicate invitation, :direct_member?
    end

    test "properly sets role to :admin" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
      )
      invitation.role = :admin
      invitation.save
      invitation.reload

      assert_predicate invitation, :admin?
    end
  end

  context "show_inviter?" do
    test "true when the inviter is a user other than the inviting org" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])

      assert invitation.show_inviter?
    end

    test "false when the inviter is the same as the org that the invitation is for" do
      invitation = @org.invite(@invitee, inviter: @org, teams: [create(:team, organization: @org)])

      refute invitation.show_inviter?
    end

    test "false when the inviter has been deleted" do
      inviter = create(:user, login: "inviter")
      @org.add_admin(inviter)

      invitation = @org.invite(@invitee, inviter: inviter, teams: [create(:team, organization: @org)])

      @org.remove_member!(inviter)
      assert inviter.destroy

      refute invitation.reload.show_inviter?
    end

    test "false when the inviter is a Bot" do
      github_app = create(:integration, default_permissions: { "members" => :write })
      installation = make_integration_installation(
        target: @org,
        integration: github_app)
      # Manually assign the installation for this test, as this would be carried out
      # during API request by an installation to create this invitation.
      github_app.bot.installation = installation
      assert @org.resources.members.writable_by?(installation)

      invitation = @org.invite(@invitee, inviter: github_app.bot, teams: [create(:team, organization: @org)])

      refute invitation.show_inviter?
    end
  end

  context "email_or_invitee_name" do
    test "returns invitee safe profile name for invitee invitation" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      assert_equal @invitee.safe_profile_name, invitation.email_or_invitee_name
    end

    test "returns email for email invitation" do
      invitation = @org.invite(email: "garrett@github.com", inviter: @inviter, teams: [create(:team, organization: @org)])
      assert_equal "garrett@github.com", invitation.email_or_invitee_name
    end

    test "returns nil if invitee and email are missing" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.update_column :invitee_id, 0
      assert_nil invitation.email_or_invitee_name
    end
  end

  context "email_or_invitee_login" do
    test "returns invitee login for invitee invitation" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      assert_equal @invitee.login, invitation.email_or_invitee_login
    end

    test "returns email for email invitation" do
      invitation = @org.invite(email: "garrett@github.com", inviter: @inviter, teams: [create(:team, organization: @org)])
      assert_equal "garrett@github.com", invitation.email_or_invitee_login
    end

    test "returns nil if invitee and email are missing" do
      invitation = @org.invite(@invitee, inviter: @inviter, teams: [create(:team, organization: @org)])
      invitation.update_column :invitee_id, 0
      assert_nil invitation.email_or_invitee_login
    end
  end

  context "except_with_role" do
    test "excludes invitation with given role" do
      admin_invite = create(:organization_invitation, role: :admin)
      refute_includes OrganizationInvitation.except_with_role(:admin),
                      admin_invite
    end

    test "includes invitation that does not have given role" do
      admin_invite = create(:organization_invitation, role: :admin)
      assert_includes OrganizationInvitation.except_with_role(:direct_member),
                      admin_invite
    end

    test "excludes invitations with any of the given roles" do
      admin_invite = create(:organization_invitation, role: :admin)
      manager_invite = create(:organization_invitation, role: :billing_manager)
      results = OrganizationInvitation.except_with_role(:admin, :billing_manager)
      refute_includes results, admin_invite
      refute_includes results, manager_invite
    end

    test "includes invitations that don't have any of the given roles" do
      admin_invite = create(:organization_invitation, role: :admin)
      manager_invite = create(:organization_invitation, role: :billing_manager)
      member_invite = create :organization_invitation
      results = OrganizationInvitation.except_with_role(:admin, :billing_manager)
      assert_includes results, member_invite
    end
  end

  context "#email=" do
    test "sets the normalized email as well" do
      invite = OrganizationInvitation.new
      invite.email = "john.smith@gmail.com"

      assert_equal "john.smith@gmail.com", invite.email
      assert_equal "johnsmith@gmail.com", invite.normalized_email
    end

    test "sets the normalized email to nil if unable to normalize" do
      invite = OrganizationInvitation.new email: "john.smith@gmail.com"

      invite.email = nil
      assert_nil invite.normalized_email

      invite.email = ""
      assert_nil invite.normalized_email

      invite.email = "bad-email"
      assert_nil invite.normalized_email

      invite.email = "bad email@example.com"
      assert_nil invite.normalized_email
    end
  end

  context "token" do
    test "does not generate token if no email is present" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee,
        role: :direct_member,
      )

      assert invitation.valid?
      refute_predicate invitation.token, :present?
      refute_predicate invitation.hashed_token, :present?
    end

    test "generates token if email is present" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        email: "garrett@github.com",
        role: :direct_member,
      )

      assert invitation.valid?
      assert_predicate invitation.token, :present?
      assert_predicate invitation.hashed_token, :present?
    end

    test "only stores the hashed token" do
      persisted_invitation = create(:organization_invitation,
        organization: @org,
        inviter: @inviter,
        invitee: nil,
        email: "garrett@github.com",
        role: :direct_member,
      )

      invitation = OrganizationInvitation.find(persisted_invitation.id)
      refute_predicate invitation.token, :present?
      assert_predicate invitation.hashed_token, :present?
    end

    test "allows the token to be reset" do
      invitation = create(:organization_invitation,
        organization: @org,
        inviter: @inviter,
        invitee: nil,
        email: "garrett@github.com",
        role: :direct_member,
      )

      old_token = invitation.token
      invitation.reset_token

      refute_equal old_token, invitation.token
      assert_equal invitation, OrganizationInvitation.find_by_token(invitation.token)
    end
  end

  context "#prevented_by_trade_controls_restrictions?" do
    test "returns true if org is full restricted" do
      free_org = create(:free_org)
      free_org.trade_controls_restriction.full!

      invitation = create(:organization_invitation, organization: free_org)

      assert invitation.prevented_by_trade_controls_restrictions?
    end

    test "returns false if inviter is flagged on paid org" do
      @inviter.trade_controls_restriction.full!

      invitation = create(:organization_invitation, organization: @org, inviter: @inviter)

      refute invitation.prevented_by_trade_controls_restrictions?
    end

    test "returns false if invitee is flagged on paid org" do
      @invitee.trade_controls_restriction.full!

      invitation = create(:organization_invitation, organization: @org, invitee: @invitee)

      refute invitation.prevented_by_trade_controls_restrictions?
    end

    test "returns false if invitee is flagged on free org" do
      free_org = create(:free_org)
      @invitee.trade_controls_restriction.full!

      invitation = create(:organization_invitation, organization: free_org, invitee: @invitee)

      refute invitation.prevented_by_trade_controls_restrictions?
    end

    test "returns false if inviter is flagged on free org" do
      free_org = create(:free_org)
      @inviter.trade_controls_restriction.full!

      invitation = create(:organization_invitation, organization: free_org, inviter: @inviter)

      refute invitation.prevented_by_trade_controls_restrictions?
    end

    test "returns false if org is partially restricted" do
      free_org = create(:free_org)
      free_org.trade_controls_restriction.partial!

      invitation = create(:organization_invitation, organization: free_org)

      refute invitation.prevented_by_trade_controls_restrictions?
    end
  end

  context "#created_by_external_identity_provider?" do
    test "returns false for manual invite" do
      invitation = OrganizationInvitation.new(
        organization: @org,
        inviter: @inviter,
        invitee: @invitee)

      refute invitation.created_by_external_identity_provider?
    end

    test "returns true for SCIM provision originated invite", skip_enterprise: true do
      provider = create(:organization_saml_provider)
      org = provider.organization

      assert_equal 0, org.saml_provider.external_identities.count
      assert_equal 0, org.pending_invitations.count

      scim_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
      scim_user_data.append "userName", @invitee.email
      scim_user_data.append "emails", @invitee.email

      Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(
        organization_id: org.id,
        user_data: scim_user_data,
        inviter_id: org.members.first.id,
        mapper: Platform::Provisioning::ScimMapper)

      assert_equal 1, org.saml_provider.external_identities.count
      assert_equal 1, org.pending_invitations.count

      invitation = org.pending_invitation_for(email: @invitee.email)
      assert invitation.created_by_external_identity_provider?
    end
  end

  context "expiration" do
    test "expires regular invitations" do
      regular_invite = T.let(nil, T.nilable(OrganizationInvitation))
      Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        regular_invite = @org.invite(@invitee, inviter: @inviter)

        assert_predicate regular_invite, :can_expire?
      end

      assert T.must(regular_invite).invite_expired?
      assert_same_elements [regular_invite], OrganizationInvitation.recently_expired
    end

    test "instrument expiration invitations" do
      invitation = @org.invite(@invitee, inviter: @inviter)
      GlobalInstrumenter.expects(:instrument).with("org.member_invite_expired", has_entries(invitation: invitation)).once

      invitation.expire
    end

    test "doesn't expire IdP-initiated invitations", skip_enterprise: true do
      provider = create(:organization_saml_provider)
      org = provider.organization

      scim_invite = T.let(nil, T.nilable(OrganizationInvitation))
      Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        scim_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
        scim_user_data.append "userName", @invitee.email
        scim_user_data.append "emails", @invitee.email

        Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(
          organization_id: org.id,
          user_data: scim_user_data,
          inviter_id: org.members.first.id,
          mapper: Platform::Provisioning::ScimMapper)

        scim_invite = org.pending_invitation_for(email: @invitee.email)
        refute_predicate scim_invite, :can_expire?
      end

      refute T.must(scim_invite).invite_expired?
      assert_empty OrganizationInvitation.recently_expired
    end
  end

  context ".excluding_expired" do
    test "returns non-expired invitations (either created in last 7 days, or created by an external identity provider)", skip_enterprise: true do
      provider = create(:organization_saml_provider)
      organization = provider.organization
      organization_admin = organization.admins.first

      scim_invite = travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        scim_invitee_email = "scim@example.com"
        scim_user_data = Platform::Provisioning::AttributeMappedUserData.new(Platform::Provisioning::ScimUserData.new)
        scim_user_data.append "userName", scim_invitee_email
        scim_user_data.append "emails", scim_invitee_email

        Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(
          organization_id: organization.id,
          user_data: scim_user_data,
          inviter_id: organization_admin,
          mapper: Platform::Provisioning::ScimMapper)

        organization.pending_invitation_for(email: scim_invitee_email)
      end

      old_invite = travel_to (GitHub.invitation_expiry_period + 1).days.ago do
        organization.invite(create(:user), inviter: organization_admin)
      end

      recent_invite = organization.invite(create(:user), inviter: organization_admin)

      non_expired_invites = OrganizationInvitation.excluding_expired

      assert_includes non_expired_invites, scim_invite
      assert_includes non_expired_invites, recent_invite
      refute_includes non_expired_invites, old_invite
    end
  end

  context "licensing snapshots", skip_enterprise: true do
    include HydroTestHelpers

    test "publishes license snapshot messages when the invitation is created, updated, and destroyed if the organization is business owned" do
      business = create(:business, organizations: [@org])
      @org.reload # reload organization so that it's aware of the business

      T.unsafe(self).reset_hydro # clear any messages that were sent during setup

      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation = @org.invite(@invitee, inviter: @inviter)

        T.unsafe(self).assert_hydro_messages(count: 1, schema: "github.billing.v0.LicenseSnapshot")

        invitation.update(updated_at: 1.year.from_now)

        T.unsafe(self).assert_hydro_messages(count: 2, schema: "github.billing.v0.LicenseSnapshot")

        invitation.destroy

        T.unsafe(self).assert_hydro_messages(count: 3, schema: "github.billing.v0.LicenseSnapshot")
      end
    end

    test "does not publish license snapshot events if the organization is not business owned" do
      perform_enqueued_jobs(only: Licensing::SnapshotLicensesJob) do
        invitation = @org.invite(@invitee, inviter: @inviter)
        invitation.update(updated_at: 1.year.from_now)
        invitation.destroy
      end

      T.unsafe(self).assert_hydro_messages(count: 0, schema: "github.billing.v0.LicenseSnapshot")
    end
  end

  context "reinstating_outside_collaborator?" do
    test "returns true if the invitation is for an outside collaborator" do
      restorable_org_user = create(:restorable_organization_user, :complete)
      restorable = restorable_org_user.restorable
      org = restorable_org_user.organization
      restorable.memberships.create(
        subject_type: "Repository",
        subject_id: org.id,
        action: :read,
      )
      invitee = restorable_org_user.user
      invitation = org.invite(invitee, inviter: org.admin, role: :reinstate)

      assert_predicate invitation, :reinstating_outside_collaborator?
    end

    test "returns false is user is not restorable" do
      invitation = @org.invite(@invitee, inviter: @inviter, role: :reinstate)

      refute_predicate invitation, :reinstating_outside_collaborator?
    end

    test "returns false if the invitation is not for an outside collaboratorr" do
      restorable_org_user = create(:restorable_organization_user, :complete)
      restorable = restorable_org_user.restorable
      org = restorable_org_user.organization
      restorable.memberships.create(
        subject_type: "Organization",
        subject_id: org.id,
        action: :read,
      )
      restorable.memberships.create(
        subject_type: "Repository",
        subject_id: org.id,
        action: :read,
      )
      invitee = restorable_org_user.user
      invitation = org.invite(invitee, inviter: org.admin, role: :reinstate)

      refute_predicate invitation, :reinstating_outside_collaborator?
    end
  end

  context "#acceptor_needs_to_verify_email?" do
    test "returns true if the user has not verified the email address to which the email invite was addressed" do
      @invitee.add_email(@unverified_email)
      email_invite = @org.invite(email: @unverified_email, inviter: @owner)

      assert email_invite.email?
      refute @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      assert email_invite.acceptor_needs_to_verify_email?(acceptor: @invitee)
    end

    test "returns false if invitation is not an email invitation" do

      regular_invite = @org.invite(@invitee, inviter: @owner)

      refute regular_invite.email?
      refute regular_invite.acceptor_needs_to_verify_email?(acceptor: @invitee)
    end

    test "returns false if user has verified the email to which the email invite was addressed, if the invite is an email invite" do

      email_invite = @org.invite(email: @verified_email, inviter: @owner)

      assert email_invite.email?
      assert @invitee.emails.verified.pluck(:email).include?(email_invite.email)
      refute email_invite.acceptor_needs_to_verify_email?(acceptor: @invitee)
    end

    test "does not increment email verification stats by default" do
      email_invite = @org.invite(email: @verified_email, inviter: @owner)
      email_invite.acceptor_needs_to_verify_email?(acceptor: @invitee)

      assert_dogstats_increment(0, "organization_invitation.verified_email")
    end

    test "increments email verification stats with verified email" do
      email_invite = @org.invite(email: @verified_email, inviter: @owner)
      email_invite.acceptor_needs_to_verify_email?(acceptor: @invitee, instrument: true)

      assert_dogstats_increment("organization_invitation.verified_email", tags: [
        "email_verification_enabled:true",
        "verified_email:true",
      ])
    end

    test "increments email verification stats with unverified email" do
      @invitee.add_email(@unverified_email)
      email_invite = @org.invite(email: @unverified_email, inviter: @owner)

      email_invite.acceptor_needs_to_verify_email?(acceptor: @invitee, instrument: true)

      assert_dogstats_increment("organization_invitation.verified_email", tags: [
        "email_verification_enabled:true",
        "verified_email:false",
      ])
    end
  end
end unless GitHub.bypass_org_invites_enabled?
