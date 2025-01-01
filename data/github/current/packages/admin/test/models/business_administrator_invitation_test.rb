# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAdministratorInvitationTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create :user
    @org_member = create :user
    @billing_manager = create :user
    @admin = create :user
    @another_admin = create :user
    @invitee = create :user
    @invitee.emails.each(&:verify!)

    @org = create :organization
    @org.add_member(@org_member)

    @business = create :business, owners: [@admin, @another_admin], organizations: [@org]
    @business.customer.update!(billed_via_billing_platform: true)
    @business.billing.add_manager @billing_manager, actor: @admin

    @staff = create :staff_admin_user
    @inviter = @admin
    @invitation = create :business_administrator_invitation, role: :owner, \
      business: @business, inviter: @inviter, invitee: @invitee
    @email_invitation = create :business_administrator_invitation, :email, \
      role: :owner, business: @business, inviter: @inviter, email: "hi@examp.le"
    @billing_manager_invitation = create :business_administrator_invitation, \
      business: @business, inviter: @billing_manager, invitee: @invitee, \
      role: :billing_manager
    @unaffiliated_invitation = create :business_administrator_invitation, \
      business: @business, inviter: @inviter, invitee: @invitee, \
      role: :unaffiliated
  end

  setup do
    GitHub.stubs(:single_business_environment?).returns(false)
    Failbot.reports.clear
  end

  context "instrumentation" do
    test "instruments inviting admin via login" do
      invitee = create :user
      events = subscribe("business.invite_admin")
      invitation = @business.invite_admin user: invitee, inviter: @inviter, role: :owner

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_admin", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting admin via email" do
      events = subscribe("business.invite_admin")
      invitation = @business.invite_admin email: "again@examp.le", inviter: @inviter, role: :owner

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_admin", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting billing manager via login" do
      invitee = create :user
      events = subscribe("business.invite_billing_manager")
      invitation = @business.invite_admin(user: invitee, inviter: @inviter, role: :billing_manager)

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting billing manager via email" do
      events = subscribe("business.invite_billing_manager")
      invitation = @business.invite_admin(email: "again@examp.le", inviter: @inviter, role: :billing_manager)

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting unaffiliated member via login" do
      invitee = create :user
      events = subscribe("business.invite_unaffiliated_member")
      invitation = @business.invite_admin(user: invitee, inviter: @inviter, role: :unaffiliated)

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_unaffiliated_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting unaffiliated member via email" do
      events = subscribe("business.invite_unaffiliated_member")
      invitation = @business.invite_admin(email: "again@examp.le", inviter: @inviter, role: :unaffiliated)

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_unaffiliated_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "masks stafftools user", skip_enterprise: true do
    test "instruments inviting admin via login" do
      invitee = create :user
      events = subscribe("business.invite_admin")
      invitation = @business.invite_admin user: invitee, inviter: @staff, role: :owner, stafftools_invite: true

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_admin", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting admin via email" do
      events = subscribe("business.invite_admin")
      invitation = @business.invite_admin email: "again@examp.le", inviter: @staff, role: :owner, stafftools_invite: true

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_admin", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting billing manager via login" do
      invitee = create :user
      events = subscribe("business.invite_billing_manager")
      invitation = @business.invite_admin(user: invitee, inviter: @staff, role: :billing_manager, stafftools_invite: true)

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting billing manager via email" do
      events = subscribe("business.invite_billing_manager")
      invitation = @business.invite_admin(email: "again@examp.le", inviter: @staff, role: :billing_manager, stafftools_invite: true)

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting unaffiliated member via login" do
      invitee = create :user
      events = subscribe("business.invite_unaffiliated_member")
      invitation = @business.invite_admin(user: invitee, inviter: @staff, role: :unaffiliated, stafftools_invite: true)

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_unaffiliated_member", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments inviting unaffiliated member via email" do
      events = subscribe("business.invite_unaffiliated_member")
      invitation = @business.invite_admin(email: "again@examp.le", inviter: @staff, role: :unaffiliated, stafftools_invite: true)

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        email: invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: invitation.id,
      }
      refute_nil event = events.pop
      assert_equal "business.invite_unaffiliated_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#send_nurture_request" do
    context "when business is part of startup program and from stafftools" do
      test "queues nurture request job" do
        create(:business_startups_program, business: @business)
        invitation = create :business_administrator_invitation, \
          role: :owner, business: @business, inviter: @inviter, stafftools_invite: true

        StartupProgramNurtureRequestJob.expects(:perform_later).once.with(
          admin_email: @inviter.email,
          email: invitation.invitee.email,
        ).returns(nil)

        invitation.send_nurture_request
      end

      test "queue request with email if there is no invitee email" do
        create(:business_startups_program, business: @business)
        invitee_email = "hello@example.com"
        invitation = create :business_administrator_invitation, :email, email: invitee_email, \
          role: :owner, business: @business, inviter: @inviter, stafftools_invite: true

        StartupProgramNurtureRequestJob.expects(:perform_later).once.with(
          admin_email: @inviter.email,
          email: invitee_email,
        ).returns(nil)

        invitation.send_nurture_request
      end
    end

    test "does not queue nurture request job if business is not part of startup program and from stafftools" do
      invitation = create :business_administrator_invitation, \
        role: :owner, business: @business, inviter: @inviter, stafftools_invite: true

      StartupProgramNurtureRequestJob.expects(:perform_later).never.with(
        admin_email: @inviter.email,
        email: invitation.invitee.email,
      ).returns(nil)

      invitation.send_nurture_request
    end

    test "does not queue nurture request job if business is part of startup program and not from stafftools" do
      invitation = create :business_administrator_invitation, \
        role: :owner, business: @business, inviter: @inviter, stafftools_invite: false

      StartupProgramNurtureRequestJob.expects(:perform_later).never.with(
        admin_email: @inviter.email,
        email: invitation.invitee.email,
      ).returns(nil)

      invitation.send_nurture_request
    end
  end

  context "#send_invitation_email" do
    test "queues mail delivery for owner invitation with invitee" do
      invitation = create :business_administrator_invitation, \
        role: :owner, business: @business, inviter: @inviter

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, nil, nil
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for owner invitation with invitee with stafftools_invite true" do
      invitation = create :business_administrator_invitation, \
        role: :owner, business: @business, inviter: @inviter, stafftools_invite: true

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, nil, nil
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for owner invitation with invitee with reinvited_count set" do
      invitation = create :business_administrator_invitation, \
        role: :owner, business: @business, inviter: @inviter, reinvited_count: 1

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, nil, 1
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for owner invitation with email" do
      invitation = create :business_administrator_invitation, :email, \
        role: :owner, business: @business, inviter: @inviter,
        email: "hello@example.com"

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, invitation.token, nil
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for owner invitation with email with stafftools_invite true" do
      invitation = create :business_administrator_invitation, :email, \
        role: :owner, business: @business, inviter: @inviter,
        email: "hello@example.com", stafftools_invite: true

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, invitation.token, nil
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for owner invitation with email with reinvited_count set" do
      invitation = create :business_administrator_invitation, :email, \
        role: :owner, business: @business, inviter: @inviter,
        email: "hello@example.com", reinvited_count: 1

      BusinessMailer.expects(:invited_as_business_owner).once.with(
        invitation, invitation.token, 1
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for billing manager invitation" do
      invitation = create :business_administrator_invitation, \
        role: :billing_manager, business: @business, inviter: @inviter

      BusinessMailer.expects(:invited_as_business_billing_manager).once.with(
        invitation, invitation.token
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end

    test "queues mail delivery for unaffiliated member invitation" do
      invitation = create :business_administrator_invitation, \
        role: :unaffiliated, business: @business, inviter: @inviter

      BusinessMailer.expects(:invited_as_business_unaffiliated_member).once.with(
        invitation, invitation.token
      ).returns(stub(deliver_later: nil))

      invitation.send_invitation_email
    end
  end

  context "#pending" do
    test "finds pending business member invitations" do
      accepted_invitation = create :business_administrator_invitation
      accepted_invitation.accept
      cancelled_invitation = create :business_administrator_invitation
      cancelled_invitation.cancel(actor: @inviter)
      expired_invitation = create :business_administrator_invitation
      expired_invitation.expire

      assert_same_elements \
        [@invitation, @email_invitation, @billing_manager_invitation, \
          @unaffiliated_invitation, \
          accepted_invitation, cancelled_invitation, expired_invitation], \
          BusinessAdministratorInvitation.all
      assert_same_elements \
        [@invitation, @email_invitation, @billing_manager_invitation, \
          @unaffiliated_invitation,], \
          BusinessAdministratorInvitation.pending
    end
  end

  context "#expired" do
    test "finds only expired invitations" do
      accepted_invitation = create :business_administrator_invitation
      accepted_invitation.accept
      cancelled_invitation = create :business_administrator_invitation
      cancelled_invitation.cancel(actor: @inviter)
      expired_invitation = create :business_administrator_invitation
      expired_invitation.expire

      assert_same_elements \
        [
          @invitation, @email_invitation, @billing_manager_invitation, \
          @unaffiliated_invitation, \
          accepted_invitation, cancelled_invitation, expired_invitation
        ],
        BusinessAdministratorInvitation.all
      assert_same_elements [expired_invitation], BusinessAdministratorInvitation.expired
    end
  end

  context "#recently_expired" do
    test "includes invitations that expired within the cutoff" do
      invitation = Timecop.travel((GitHub.invitation_expiry_period + 1).days.ago) do
        create :business_administrator_invitation, business: @business
      end
      assert_same_elements [invitation], BusinessAdministratorInvitation.recently_expired
    end

    test "does not include invitations that expired before the cutoff" do
      invitation = Timecop.travel((GitHub.invitation_expiry_cutoff + 1).days.ago) do
        create :business_administrator_invitation, business: @business
      end
      assert_empty BusinessAdministratorInvitation.recently_expired
    end
  end

  context "#pending?" do
    test "false when invitation is accepted" do
      assert_predicate @invitation, :pending?
      @invitation.accept
      refute_predicate @invitation, :pending?
    end

    test "false when invitation is cancelled" do
      assert_predicate @invitation, :pending?
      @invitation.cancel(actor: @inviter)
      refute_predicate @invitation, :pending?
    end

    test "true when invitation is not accepted or cancelled" do
      refute_predicate @invitation, :accepted?
      refute_predicate @invitation, :cancelled?
      assert_predicate @invitation, :pending?
    end
  end

  context "#accept" do
    test "raises BusinessAdministratorInvitation::ExpiredError if expired" do
      @invitation.expire
      @invitation.reload

      assert_raises(BusinessAdministratorInvitation::ExpiredError) do
        @invitation.accept acceptor: @invitee
      end
    end

    test "raises BusinessAdministratorInvitation::CanceledError if canceled" do
      @invitation.cancel(actor: @inviter)
      @invitation.reload

      assert_raises(BusinessAdministratorInvitation::CanceledError) do
        @invitation.accept acceptor: @invitee
      end
    end

    test "raises BusinessAdministratorInvitation::AlreadyAcceptedError if already accepted" do
      @invitation.accept acceptor: @invitee
      @invitation.reload

      assert_raises(BusinessAdministratorInvitation::AlreadyAcceptedError) do
        @invitation.accept acceptor: @invitee
      end
    end

    test "raises BusinessAdministratorInvitation::InvalidAcceptorError if acceptor is not invitee" do
      assert_raises(BusinessAdministratorInvitation::InvalidAcceptorError) do
        @invitation.accept acceptor: create(:user)
      end
    end

    test "raises BusinessAdministratorInvitation::AcceptorAlreadyOwnerError when invitee is already an owner and invited when role is :billing_manager" do
      @business.add_owner(@invitee, actor: @admin)
      assert @business.owner?(@invitee)
      refute @business.billing_manager?(@invitee)

      billing_manager_invitation = create :business_administrator_invitation,
        business: @business,
        inviter: @inviter,
        invitee: @invitee,
        role: :billing_manager

      assert_raises(BusinessAdministratorInvitation::AcceptorAlreadyOwnerError) do
        billing_manager_invitation.accept(acceptor: @invitee)
      end

      assert @business.owner?(@invitee)
      refute @business.billing_manager?(@invitee)
    end

    test "raises BusinessAdministratorInvitation::AcceptorAlreadyOwnerError when acceptor is already an owner and invited when role is :billing_manager" do
      acceptor = create :user
      @business.add_owner(acceptor, actor: @admin)
      assert @business.owner?(acceptor)
      refute @business.billing_manager?(acceptor)

      billing_manager_invitation = create :business_administrator_invitation,
        :email,
        business: @business,
        inviter: @inviter,
        email: "whoever@example.com",
        role: :billing_manager

      assert_raises(BusinessAdministratorInvitation::AcceptorAlreadyOwnerError) do
        billing_manager_invitation.accept(acceptor: acceptor, via_email: true)
      end

      assert @business.owner?(acceptor)
      refute @business.billing_manager?(acceptor)
    end

    test "adds the invitee as a business admin when role is :owner" do
      refute @business.owner?(@invitee)
      @invitation.accept acceptor: @invitee

      assert @business.owner?(@invitee)
    end

    test "adds the invitee as a business billing manager when role is :billing_manager" do
      refute @business.owner?(@invitee)
      refute @business.billing_manager?(@invitee)
      billing_manager_invitation = create :business_administrator_invitation, \
        business: @business, inviter: @inviter, invitee: @invitee, \
        role: :billing_manager
      billing_manager_invitation.accept acceptor: @invitee

      assert @business.billing_manager?(@invitee)
      refute @business.owner?(@invitee)
    end

    test "adds the invitee as an unaffiliated member when role is :unaffiliated" do
      GitHub.flipper[:unaffiliated_user_accounts].enable
      refute @business.owner?(@invitee)
      member_invitation = create :business_administrator_invitation, \
        business: @business, inviter: @inviter, invitee: @invitee, \
        role: :unaffiliated
      member_invitation.accept acceptor: @invitee

      refute @business.owner?(@invitee)
      refute @business.member?(@invitee)
      assert @business.unaffiliated_member?(@invitee)
      assert_equal 0, @business.business_user_account_for(@invitee).business_roles_bitfield
    end

    test "instruments business.add_admin event with correct attribution" do
      events = subscribe "business.add_admin"
      @invitation.accept acceptor: @invitee

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: @invitee.login,
        user_id: @invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
      }

      refute_nil event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "masks staff information if invite was initiated from stafftools", skip_enterprise: true do
      invitee = create :user
      events = subscribe "business.add_admin"
      invitation = @business.invite_admin user: invitee, inviter: @staff, role: :owner, stafftools_invite: true

      invitation.accept acceptor: invitee

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        user: invitee.login,
        user_id: invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
      }
      refute_nil event = events.pop
      assert_equal "business.add_admin", event.name
      assert_equal expected_payload, event.payload
    end

    test "masks staff inforamtion if invite was initiated from stafftools for billing manager", skip_enterprise: true do
      events = subscribe "business.add_billing_manager"

      billing_manager_invitation = create :business_administrator_invitation, \
      business: @business, inviter: @staff, invitee: @invitee, \
      role: :billing_manager, stafftools_invite: true

      billing_manager_invitation.accept acceptor: @invitee

      expected_payload = {
        staff_actor: @staff.display_login,
        staff_actor_id: @staff.id,
        actor:  User.staff_user.display_login,
        actor_id: User.staff_user.id,
        user: @invitee.login,
        user_id: @invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
      }
      refute_nil event = events.pop
      assert_equal "business.add_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "accepted?" do
    test "false before the invitation has been accepted" do
      refute_predicate @invitation, :accepted?
    end

    test "true after the invitation has been accepted" do
      @invitation.accept
      assert_predicate @invitation, :accepted?
    end
  end

  context "#cancel" do
    test "cancels the invitation when pending" do
      assert_predicate @invitation, :pending?
      Timecop.freeze(Time.zone.local(2017, 2, 2, 2, 0, 0)) do |cancelled_at|
        assert_no_difference("BusinessAdministratorInvitation.count") do
          @invitation.cancel actor: @inviter
        end
        assert_equal cancelled_at, @invitation.reload.cancelled_at
      end
    end

    test "cancels an invitation when pending even if the inviter has been deleted" do
      @business.remove_owner @inviter, actor: @another_admin
      @inviter.destroy!
      assert_predicate @invitation, :pending?
      Timecop.freeze(Time.zone.local(2017, 2, 2, 2, 0, 0)) do |cancelled_at|
        assert_no_difference("BusinessAdministratorInvitation.count") do
          @invitation.cancel actor: @another_admin
        end
        assert_equal cancelled_at, @invitation.reload.cancelled_at
      end
    end

    test "raises BusinessAdministratorInvitation::AlreadyAcceptedError when accepted" do
      @invitation.accept

      assert_no_difference "BusinessAdministratorInvitation.count" do
        assert_raises BusinessAdministratorInvitation::AlreadyAcceptedError do
          @invitation.cancel actor: @inviter
        end
      end
    end

    test "instruments business.cancel_admin_invitation event" do
      events = subscribe "business.cancel_admin_invitation"
      @invitation.cancel actor: @inviter

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        user: @invitee.login,
        user_id: @invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: @invitation.id,
      }

      refute_nil event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "instruments business.cancel_admin_invitation event for email invitation" do
      events = subscribe "business.cancel_admin_invitation"
      @email_invitation.cancel actor: @inviter

      expected_payload = {
        actor: @inviter.login,
        actor_id: @inviter.id,
        email: @email_invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: @email_invitation.id,
      }

      refute_nil event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "instruments business.cancel_billing_manager_invitation event" do
      events = subscribe "business.cancel_billing_manager_invitation"
      @billing_manager_invitation.cancel actor: @billing_manager

      expected_payload = {
        actor: @billing_manager.login,
        actor_id: @billing_manager.id,
        user: @invitee.login,
        user_id: @invitee.id,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        spammy: @invitee.spammy,
        invitation_id: @billing_manager_invitation.id,
      }

      refute_nil event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "instruments business.cancel_billing_manager_invitation event for email invitation" do
      email_invitation = create :business_administrator_invitation, :email, \
        role: :billing_manager,
        business: @business,
        inviter: @billing_manager,
        email: "hi@billi.ng"
      events = subscribe "business.cancel_billing_manager_invitation"
      email_invitation.cancel actor: @billing_manager

      expected_payload = {
        actor: @billing_manager.login,
        actor_id: @billing_manager.id,
        email: email_invitation.email,
        name: @business.name,
        business: @business.slug,
        business_id: @business.id,
        invitation_id: email_invitation.id,
      }

      refute_nil event = events.pop
      assert_equal expected_payload, event.payload
    end
  end

  context "#cancelable_by?" do
    test "true for business admin for admin invitation" do
      assert @invitation.cancelable_by?(@business.owners.first)
    end

    test "false for others for admin invitation" do
      refute @invitation.cancelable_by?(create(:user))
    end

    test "true for business admin for billing manager invitation" do
      assert @billing_manager_invitation.cancelable_by?(@business.owners.first)
    end

    test "true for business billing managers for billing manager invitation" do
      assert @billing_manager_invitation.cancelable_by?(@billing_manager)
    end

    test "false for others for billing manager invitation" do
      refute @billing_manager_invitation.cancelable_by?(create(:user))
    end

    test "true for business admin for unaffiliated invitation" do
      assert @unaffiliated_invitation.cancelable_by?(@business.owners.first)
    end

    test "false for others for unaffiliated invitation" do
      refute @unaffiliated_invitation.cancelable_by?(create(:user))
    end

  end

  context "#show_inviter?" do
    test "returns true when inviter exists and stafftools_invite is false" do
      refute_nil @invitation.inviter
      refute_predicate @invitation, :stafftools_invite?
      assert_predicate @invitation, :show_inviter?
    end

    test "returns false when stafftools_invite is true" do
      @invitation.update! stafftools_invite: true
      refute_nil @invitation.inviter
      assert_predicate @invitation, :stafftools_invite?
      refute_predicate @invitation, :show_inviter?
    end

    test "returns false when inviter does not exist" do
      @business.remove_owner @invitation.inviter, actor: @another_admin
      @invitation.inviter.destroy
      assert_nil @invitation.reload.inviter
      refute_predicate @invitation, :stafftools_invite?
      refute_predicate @invitation, :show_inviter?
    end
  end

  context "#cancelled?" do
    test "false when invitation is pending or accepted" do
      refute_predicate @invitation, :cancelled?
      @invitation.accept acceptor: @invitee
      refute_predicate @invitation.reload, :cancelled?
    end

    test "true when invitation is cancelled" do
      @invitation.cancel actor: @inviter
      assert_predicate @invitation.reload, :cancelled?
    end
  end

  context "#expire" do
    test "expires the invitation when pending" do
      assert_predicate @invitation, :pending?
      refute_predicate @invitation, :expired?
      Timecop.freeze(Time.zone.local(2017, 2, 2, 2, 0, 0)) do |expired_at|
        assert_no_difference("BusinessAdministratorInvitation.count") do
          @invitation.expire
        end
        assert_equal expired_at, @invitation.reload.expired_at
      end
      assert_predicate @invitation, :expired?
    end

    test "invokes reinvite logic by default" do
      assert_predicate @invitation, :pending?
      refute_predicate @invitation, :expired?

      @invitation.expects(:reinvite_on_expiry).once
      @invitation.expire

      assert_predicate @invitation, :expired?
    end

    test "does not invoke reinvite logic when skipped" do
      assert_predicate @invitation, :pending?
      refute_predicate @invitation, :expired?

      @invitation.expects(:reinvite_on_expiry).never
      @invitation.expire(skip_reinvite: true)

      assert_predicate @invitation, :expired?
    end
  end

  context "#expired?" do
    test "false when invitation is pending" do
      refute_predicate @invitation, :expired?
    end

    test "false when invitation is accepted" do
      @invitation.accept acceptor: @invitee
      refute_predicate @invitation.reload, :expired?
    end

    test "false when invitation is cancelled" do
      @invitation.cancel actor: @inviter
      refute_predicate @invitation.reload, :expired?
    end

    test "true when invitation is expired" do
      @invitation.expire
      assert_predicate @invitation.reload, :expired?
    end
  end

  context "#should_be_reinvited_on_expiry?" do
    test "returns true for newly expired owner invitation to enterprise account with no owners" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      assert_predicate invitation, :owner?
      assert_empty invitation.business.owners
      assert_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns true for expired owner invitation to enterprise account with no owners with re-invited count <= 3" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      GitHub.kv.set(invitation.reinvited_count_key, "1") # rubocop:todo GitHub/DoNotUseGlobalKv
      invitation.expire

      assert_predicate invitation, :expired?
      assert_predicate invitation, :owner?
      assert_empty invitation.business.owners
      assert_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns false for expired owner invitation to enterprise account with no owners if business is soft-deleted" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      GitHub.kv.set(invitation.reinvited_count_key, "1") # rubocop:todo GitHub/DoNotUseGlobalKv
      business.soft_delete!
      assert_predicate business, :deleted?

      invitation.reload.expire

      assert_predicate invitation, :expired?
      assert_predicate invitation, :owner?
      refute_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns false for expired owner invitation to enterprise account with no owners with re-invited count == 3" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      GitHub.kv.set(invitation.reinvited_count_key, "3") # rubocop:todo GitHub/DoNotUseGlobalKv
      invitation.expire

      assert_predicate invitation, :expired?
      assert_predicate invitation, :owner?
      assert_empty invitation.business.owners
      refute_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns false if invitation is not expired" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true

      assert_predicate invitation, :owner?
      assert_empty invitation.business.owners
      refute_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns false for a billing manager invitation" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :billing_manager, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      assert_empty invitation.business.owners
      refute_predicate invitation, :should_be_reinvited_on_expiry?
    end

    test "returns false if the business already has at least one owner" do
      business = create :business, owners: [@admin]
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      assert_predicate invitation, :owner?
      refute_predicate invitation, :should_be_reinvited_on_expiry?
    end
  end

  context "#reinvite_on_expiry" do
    test "re-invites by email for newly expired owner invitation to enterprise account with no owners" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, :email, role: :owner, \
        business: business, inviter: @staff, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      new_invitation = business.invitations.pending.find_by email: invitation.email
      refute_predicate new_invitation, :expired?
      assert_equal invitation.business, new_invitation.business
      assert_nil new_invitation.invitee
      assert_equal invitation.email, new_invitation.email
      assert_equal invitation.inviter, new_invitation.inviter
      assert_equal invitation.role, new_invitation.role
    end

    test "re-invites with invitee for newly expired owner invitation to enterprise account with no owners" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      new_invitation = business.invitations.pending.find_by invitee: @invitee
      refute_predicate new_invitation, :expired?
      assert_equal invitation.business, new_invitation.business
      assert_nil new_invitation.email
      assert_equal invitation.invitee, new_invitation.invitee
      assert_equal invitation.inviter, new_invitation.inviter
      assert_equal invitation.role, new_invitation.role
    end

    test "re-invites for expired site admin initiated invitation even if the original inviter is no longer a site admin" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner,
        business: business, inviter: @staff, invitee: @invitee, stafftools_invite: true
      @staff.revoke_privileged_access "Reasons"

      invitation.expire

      assert_predicate invitation, :expired?
      assert new_invitation = business.invitations.pending.find_by(invitee: @invitee)
      refute_predicate new_invitation, :expired?
      assert_equal invitation.business, new_invitation.business
      assert_nil new_invitation.email
      assert_equal invitation.invitee, new_invitation.invitee
      assert_equal invitation.inviter, new_invitation.inviter
      assert_equal invitation.role, new_invitation.role
    end

    test "reports to Failbot if an error occurs when re-inviting, without raising an error" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, :email, role: :owner, \
        business: business, inviter: @staff, stafftools_invite: true

      # Manually expire the invitation without triggering the reinvite function
      invitation.update_column :expired_at, (GitHub.invitation_expiry_period + 1).days.ago
      # Example failure: make the original invitation invalid for whatever reason
      invitation.update_column :email, "blah"

      invitation.reinvite_on_expiry

      assert_predicate invitation, :expired?
      assert_equal 1, Failbot.reports.size
      report = Failbot.reports.last
      assert_equal \
        "Failed to re-invite recipient for BusinessAdministratorInvitation with ID #{invitation.id}: Invite must be for a valid email address",
        Failbot.exception_message_from_hash(report)
    end

    test "stores correct re-invite count on first re-invite" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, :email, role: :owner, \
        business: business, inviter: @staff, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      new_invitation = business.invitations.pending.find_by email: invitation.email
      assert new_invitation
      assert_equal 1, new_invitation.times_reinvited
    end

    test "publishes a message to Hydro on re-invite with email" do
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, :email, role: :owner, \
        business: business, inviter: @staff, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      new_invitation = business.invitations.pending.find_by email: invitation.email
      assert new_invitation

      assert_hydro_published({
        old_invitation: Hydro::EntitySerializer.enterprise_admin_invitation(invitation),
        new_invitation: Hydro::EntitySerializer.enterprise_admin_invitation(new_invitation),
        times_reinvited: 1
      }, schema: "github.enterprise_account.v0.AdminReinvited")
      assert_hydro_messages(count: 1, schema: "github.enterprise_account.v0.AdminReinvited")
    end

    test "publishes a message to Hydro on re-invite with invitee" do
      invitee = create :user
      business = create :business, owners: []
      invitation = create :business_administrator_invitation, role: :owner, \
        business: business, invitee: invitee, inviter: @staff, stafftools_invite: true
      invitation.expire

      assert_predicate invitation, :expired?
      new_invitation = business.invitations.pending.find_by email: invitation.email
      assert new_invitation

      assert_hydro_published({
        old_invitation: Hydro::EntitySerializer.enterprise_admin_invitation(invitation),
        new_invitation: Hydro::EntitySerializer.enterprise_admin_invitation(new_invitation),
        times_reinvited: 1
      }, schema: "github.enterprise_account.v0.AdminReinvited")
      assert_hydro_messages(count: 1, schema: "github.enterprise_account.v0.AdminReinvited")
    end

    test "creates a maximum of 4 invitations (3 attempts to re-inviate after the first expiry)" do
      business = create :business, owners: []
      first_invitation = create :business_administrator_invitation, :email, role: :owner, \
        business: business, inviter: @staff, stafftools_invite: true
      first_invitation.expire
      assert_predicate first_invitation, :expired?
      assert_equal 1, first_invitation.times_reinvited

      second_invitation = business.invitations.pending.find_by email: first_invitation.email
      refute_predicate second_invitation, :expired?
      assert_equal first_invitation.email, second_invitation.email
      second_invitation.expire
      assert_predicate second_invitation, :expired?
      assert_equal 2, second_invitation.times_reinvited

      third_invitation = business.invitations.pending.find_by email: second_invitation.email
      refute_predicate third_invitation, :expired?
      assert_equal second_invitation.email, third_invitation.email
      third_invitation.expire
      assert_predicate third_invitation, :expired?
      assert_equal 3, third_invitation.times_reinvited

      fourth_invitation = business.invitations.pending.find_by email: third_invitation.email
      refute_predicate fourth_invitation, :expired?
      assert_equal third_invitation.email, fourth_invitation.email
      fourth_invitation.expire
      assert_predicate fourth_invitation, :expired?

      fifth_invitation = business.invitations.pending.find_by email: fourth_invitation.email
      assert_nil fifth_invitation
    end
  end

  context "#readable_by?" do
    test "is false if user is nil" do
      refute @email_invitation.readable_by?(nil)
      refute @invitation.readable_by?(nil)
    end

    test "is false if user is not a user" do
      refute @email_invitation.readable_by?(@org)
      refute @invitation.readable_by?(@org)
    end

    context "invitations to email addresses" do
      test "is true for any user" do
        assert @email_invitation.readable_by?(@user)
        assert @email_invitation.readable_by?(@org_member)
        assert @email_invitation.readable_by?(@billing_manager)
        assert @email_invitation.readable_by?(@admin)
      end
    end

    context "for administrator invitations" do
      test "is true for business admins" do
        assert @invitation.readable_by?(@admin)
      end

      test "is false for business billing managers" do
        refute @invitation.readable_by?(@billing_manager)
      end

      test "is false for organization members" do
        refute @invitation.readable_by?(@org_member)
      end

      test "is true for the invitee" do
        assert @invitation.readable_by?(@invitee)
      end

      test "is false for any other user" do
        refute @invitation.readable_by?(@user)
      end
    end

    context "for billing manager invitations" do
      test "is true for business admins" do
        assert @billing_manager_invitation.readable_by?(@admin)
      end

      test "is true for business billing managers" do
        assert @billing_manager_invitation.readable_by?(@billing_manager)
      end

      test "is false for organization members" do
        refute @billing_manager_invitation.readable_by?(@org_member)
      end

      test "is true for the invitee" do
        assert @billing_manager_invitation.readable_by?(@invitee)
      end

      test "is false for any other user" do
        refute @billing_manager_invitation.readable_by?(@user)
      end
    end

    context "for unaffiliated member invitations" do
      test "is true for business admins" do
        assert @unaffiliated_invitation.readable_by?(@admin)
      end

      test "is false for business billing managers" do
        refute @unaffiliated_invitation.readable_by?(@billing_manager)
      end

      test "is false for organization members" do
        refute @unaffiliated_invitation.readable_by?(@org_member)
      end

      test "is true for the invitee" do
        assert @unaffiliated_invitation.readable_by?(@invitee)
      end

      test "is false for any other user" do
        refute @unaffiliated_invitation.readable_by?(@user)
      end

      test "is always false in enterprise mode" do
        GitHub.stubs(:single_business_environment?).returns(true)
        refute @unaffiliated_invitation.readable_by?(@admin)
        refute @unaffiliated_invitation.readable_by?(@billing_manager)
        refute @unaffiliated_invitation.readable_by?(@org_member)
        refute @unaffiliated_invitation.readable_by?(@invitee)
        refute @unaffiliated_invitation.readable_by?(@user)
      end
    end
  end

  context "::with_invitee_or_normalized_email" do
    test "returns invitations for an invitee" do
      @business.invite_admin user: @invitee, inviter: @inviter, role: :owner

      invitations = @business.invitations.pending.with_business_role(:owner)
        .with_invitee_or_normalized_email(invitee: @invitee)
      assert_equal 1, invitations.size
      assert_includes invitations.map(&:invitee), @invitee
    end

    test "returns invitations for an email address" do
      create :business_administrator_invitation, :email,
        business: @business, inviter: @inviter, email: "email@example.com"

      invitations = @business.invitations.pending.with_invitee_or_normalized_email(emails: "email@example.com")
      assert_equal 1, invitations.size
      assert_includes invitations.map(&:email), "email@example.com"
    end

    test "returns invitations for the email address of an invitee" do
      create :business_administrator_invitation, :email,
        business: @business, inviter: @inviter, email: @invitee.email

      invitations = @business.invitations.pending.with_invitee_or_normalized_email(emails: @invitee.email)
      assert_equal 1, invitations.size
      assert_equal invitations.first.email, @invitee.email
    end

    test "does not return invitations for other invitees" do
      create :business_administrator_invitation, :email,
        business: @business, inviter: @inviter, email: @invitee.email
      create :business_administrator_invitation,
        business: @business, inviter: @inviter, invitee: create(:user)

      invitations = @business.invitations.pending.with_invitee_or_normalized_email(emails: @invitee.email)
      assert_equal 1, invitations.size
      assert_equal invitations.first.email, @invitee.email
    end

    test "considers multiple emails" do
      create :business_administrator_invitation, :email,
        business: @business, inviter: @inviter, email: "email@example.com"

      invitations = @business.invitations.pending.with_invitee_or_normalized_email(emails: ["otheremail@example.com", "email@example.com"])
      assert_equal 1, invitations.size
      assert_equal invitations.first.email, "email@example.com"
    end
  end

  context "#role_for_message" do
    test "returns role for message for owner" do
      assert_equal "an owner", @invitation.role_for_message
    end

    test "returns role for message for billing manager" do
      assert_equal "a billing manager", @billing_manager_invitation.role_for_message
    end

    test "returns role for message for a default role" do
      @invitation.update_column :role, 0
      assert_equal "an administrator", @invitation.role_for_message
    end
  end

  context "callbacks" do
    test "when invitee is destroyed invitation is destroyed" do
      invitation_id = @invitation.id
      invitee_id = @invitation.invitee.id

      @invitee.destroy

      assert_nil User.find_by id: invitee_id
      assert_nil BusinessAdministratorInvitation.find_by id: invitation_id
    end
  end
end
