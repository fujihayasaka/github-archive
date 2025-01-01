# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessAdminsTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include TurboghasHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @owner = create :user
    @user = create :user, login: "user"
    @member1 = create(:user, :verified, login: "member1")
    @billing_manager = create :user, login: "billing-manager"

    @org1 = create :organization, plan: GitHub::Plan.business_plus, seats: 10
    @org1.add_member(@member1)

    only = [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob]
    @business = perform_enqueued_jobs only: only do
      create :business, name: "CDE Ltd", owners: [@owner], organizations: [@org1], seats: 20
    end
    @business.customer.update!(billed_via_billing_platform: true)
    @business.billing.add_manager(@billing_manager, actor: @owner)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#owner_ids" do
    test "returns IDs of business owners" do
      owner2 = create(:user)
      @business.add_owner(owner2, actor: @owner)
      assert_same_elements([@owner.id, owner2.id], @business.owner_ids)
    end
  end

  context "#owners" do
    test "allows passing them in during creation" do
      business = create :business, owners: [@user, @owner]
      assert_same_elements [@user, @owner], business.reload.owners
      assert business.owners.all? { |admin| business.adminable_by?(admin) }
    end unless GitHub.single_business_environment?

    test "raises an error when trying to bulk set owners on existing records" do
      assert_raises RuntimeError do
        @business.owners = [@user]
      end
    end
  end

  context "#pending_admin_invitation_for" do
    test "finds pending owner invitation" do
      create :business_administrator_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: @user,
        role: :owner
      invitation = @business.pending_admin_invitation_for(@user, role: :owner)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal @user, invitation.invitee
    end

    test "finds pending billing manager invitation" do
      create :business_administrator_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: @user,
        role: :billing_manager
      invitation = @business.pending_admin_invitation_for(@user, role: :billing_manager)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal @user, invitation.invitee
    end

    test "finds pending unaffiliated member invitation" do
      create :business_administrator_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: @user,
        role: :unaffiliated
      invitation = @business.pending_admin_invitation_for(@user, role: :unaffiliated)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal @user, invitation.invitee
    end

    test "finds pending owner email invitation" do
      create :business_administrator_invitation, :email, \
        business: @business,
        inviter: @business.owners.first,
        email: "hello@guacamo.le",
        role: :owner
      invitation = @business.pending_admin_invitation_for(email: "hello@guacamo.le", role: :owner)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal "hello@guacamo.le", invitation.email
    end

    test "finds pending billing manager email invitation" do
      create :business_administrator_invitation, :email, \
        business: @business,
        inviter: @business.owners.first,
        email: "hello@guacamo.le",
        role: :billing_manager
      invitation = @business.pending_admin_invitation_for(email: "hello@guacamo.le", role: :billing_manager)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal "hello@guacamo.le", invitation.email
    end

    test "finds pending unaffiliated member email invitation" do
      create :business_administrator_invitation, :email, \
        business: @business,
        inviter: @business.owners.first,
        email: "hello@guacamo.le",
        role: :unaffiliated
      invitation = @business.pending_admin_invitation_for(email: "hello@guacamo.le", role: :unaffiliated)

      assert_equal @business, invitation.business
      assert_equal @business.owners.first, invitation.inviter
      assert_equal "hello@guacamo.le", invitation.email
    end

    test "nil when neither invitee nor email provided" do
      create :business_administrator_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: @user,
        role: :owner
      create :business_administrator_invitation, :email, \
        business: @business,
        inviter: @business.owners.first,
        email: "hello@guacamo.le",
        role: :owner
      assert_nil @business.pending_admin_invitation_for(role: :owner)
    end
  end

  context "#invite_admin" do
    test "creates invitation for user without an existing pending invitation" do
      assert_nil @business.pending_admin_invitation_for(@user, role: :owner)
      invitation = @business.invite_admin user: @user, inviter: @owner, role: :owner

      assert_equal @business, invitation.business
      assert_equal @user, invitation.invitee
      assert_equal @owner, invitation.inviter
      assert_equal "owner", invitation.role
    end

    test "returns existing pending invitation for an owner" do
      existing = create :business_administrator_invitation, \
        business: @business,
        inviter: @business.owners.first,
        invitee: @user,
        role: :owner
      invitation = @business.invite_admin user: @user, inviter: @owner, role: :owner

      assert_equal invitation, existing
    end

    test "raises BusinessAdministratorInvitation::InvalidError when owner invitation is invalid" do
      @business.add_owner @user, actor: @owner # Make invitee an existing owner

      assert_raises(BusinessAdministratorInvitation::InvalidError) do
        @business.invite_admin user: @user, inviter: @owner, role: :owner
      end
    end

    test "creates invitation for billing manager without an existing pending invitation" do
      assert_nil @business.pending_admin_invitation_for(@user, role: :billing_manager)
      invitation = @business.invite_admin(user: @user, inviter: @owner, role: :billing_manager)

      assert_equal @business, invitation.business
      assert_equal @user, invitation.invitee
      assert_equal @owner, invitation.inviter
      assert_equal "billing_manager", invitation.role
    end

    test "returns existing pending invitation for a billing manager" do
      existing = create :business_administrator_invitation, \
        business: @business,
        inviter: @owner,
        invitee: @user,
        role: :billing_manager
      invitation = @business.invite_admin(user: @user, inviter: @owner, role: :billing_manager)

      assert_equal invitation, existing
    end

    test "raises BusinessAdministratorInvitation::InvalidError when billing manager invitation is invalid" do
      # Make invitee an existing billing manager
      @business.billing.add_manager @user, actor: @owner

      assert_raises(BusinessAdministratorInvitation::InvalidError) do
        @business.invite_admin(user: @user, inviter: @owner, role: :billing_manager)
      end
    end
  end

  context "#valid_administrator_state?" do
    test "returns true for user who is not suspended or deceased" do
      assert @business.valid_administrator_state?(@user)
    end

    test "returns false for user who is suspended" do
      @user.suspend "Reasons"
      refute @business.valid_administrator_state?(@user)
    end

    test "returns false for user who is deceased" do
      @user.mark_deceased
      refute @business.valid_administrator_state?(@user)
    end
  end

  context "#add_owner" do
    test "adds a single user as an owner" do
      refute @business.owner?(@user)
      @business.add_owner @user, actor: @owner
      assert @business.owner?(@user)
    end

    test "does not notify admin by email by default" do
      refute @business.owner?(@user)

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @business.add_owner @user, actor: @owner
      end
      assert @business.owner?(@user)
    end

    test "notifies admin by email when send_email_notification is true" do
      refute @business.owner?(@user)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          @business.add_owner @user, actor: @owner, send_email_notification: true
        end
      end
      assert @business.owner?(@user)
    end

    unless GitHub.single_business_environment?
      test "creates a user account for the admin if it doesn't exists" do
        refute @business.user_accounts.pluck(:user_id).include?(@user.id)
        @business.add_owner @user, actor: @owner
        assert @business.user_accounts.pluck(:user_id).include?(@user.id)
      end

      test "does not create another user account if it already exists" do
        refute @business.user_accounts.pluck(:user_id).include?(@user.id)

        org = create :organization, admin: @user
        perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { @business.add_organization(org) }
        assert @business.reload.user_accounts.pluck(:user_id).include?(@user.id)
        assert_equal 1, @business.user_accounts.pluck(:user_id).count(@user.id)

        @business.add_owner @user, actor: @owner
        assert @business.user_accounts.pluck(:user_id).include?(@user.id)
        assert_equal 1, @business.user_accounts.pluck(:user_id).count(@user.id)
      end

      test "does not send welcome email if the admin is not the first admin" do
        GitHub.flipper[:ghec_receive_net_new_enterprise_account_email].enable

        @business.expects(:send_welcome_net_new_enterprise_account_email).never

        @business.add_owner @user, actor: @owner
      end

      test "sends welcome email if the admin is the first admin" do
        GitHub.flipper[:ghec_receive_net_new_enterprise_account_email].enable

        business = create(:business, owners: [])
        owner = create(:user, login: "admin-user-2")

        business.expects(:send_welcome_net_new_enterprise_account_email).once

        business.add_owner owner, actor: owner
      end

      test "does not send welcome email if the admin is the first admin but it is a trial account" do
        GitHub.flipper[:ghec_receive_net_new_enterprise_account_email].enable

        business = create(:business, owners: [])
        business.trial_expires_at = Time.current + 30.days
        owner = create(:user, login: "admin-user-2")

        business.expects(:send_welcome_net_new_enterprise_account_email).never

        business.add_owner owner, actor: owner
      end

      if GitHub.single_business_environment?
        test "doesn't add the user to the business for single_business_environment" do
          Business.delete_all
          business = create :business, owners: [@owner]
          business.add_owner(@user, actor: @owner)
          assert_equal 0, business.user_accounts.count
        end
      end
    end

    test "raises an argument error if trying to add a non-user as an admin" do
      team = create(:team)
      assert_raises ArgumentError do
        @business.add_owner team, actor: @owner
      end
      refute @business.owner?(team)
    end

    test "raises UserHasTwoFactorDisabledError when 2FA requirement not met" do
      @business.enable_two_factor_required actor: @owner, force: true
      assert_raises Business::UserHasTwoFactorDisabledError do
        @business.add_owner @user, actor: @owner
      end
    end

    test "raises InvalidAdminStateError if user is suspended" do
      @user.suspend "Reasons"
      assert_raises Business::InvalidAdminStateError do
        @business.add_owner @user, actor: @owner
      end
    end

    test "raises InvalidAdminStateError if user is deceased" do
      @user.mark_deceased
      assert_raises Business::InvalidAdminStateError do
        @business.add_owner @user, actor: @owner
      end
    end

    test "adds an admin when 2FA requirement is met" do
      make_two_factor_credential(@user)
      refute @business.owner?(@user)
      @business.enable_two_factor_required actor: @owner, force: true
      @business.add_owner @user, actor: @owner
      assert @business.owner?(@user)
    end

    if GitHub.single_business_environment?
      test "promotes the admin as a site admin when in a single global business env" do
        GitHub.stubs(:require_employee_for_site_admin?).returns(false)

        refute GitHub.global_business.owner?(@user)
        GitHub.global_business.add_owner @user, actor: nil
        assert GitHub.global_business.owner?(@user)
        assert_predicate @user, :site_admin?
      end
    else
      test "does not promote site admin when not in a single global business env" do
        refute @business.owner?(@user)
        @business.add_owner @user, actor: nil
        assert @business.owner?(@user)
        refute_predicate @user, :site_admin?
      end
    end

    if GitHub.single_business_environment?
      test "works when businesses record has been manually inserted into the database in a single global business env" do
        Business.destroy_all
        now = Time.now
        Business.insert({ name: "I am the global business", slug: "i-am-the-global-business", created_at: now, updated_at: now })

        GitHub.stubs(:require_employee_for_site_admin?).returns(false)

        GitHub.global_business.add_owner @user, actor: nil
        assert GitHub.global_business.owner?(@user)
        assert_predicate @user, :site_admin?
      end
    end
  end

  context "#remove_owner" do
    if GitHub.single_business_environment?
      test "doesn't remove the user from the business for single_business_environment" do
        Business.delete_all
        business = create :business, owners: [@owner]
        business.add_owner(@user, actor: @owner)
        assert_equal 0, business.user_accounts.count

        business.remove_owner(@user, actor: @owner)
        assert_equal 0, business.user_accounts.count
      end
    else
      test "revokes the user's admin privileges" do
        @business.add_owner(@user, actor: @owner)
        assert @business.owner?(@owner)
        @business.remove_owner(@owner, actor: @user)
        refute @business.owner?(@owner)
      end

      test "removes the user from the business if they are not connected to the business in any other way" do
        GitHub.flipper[:unaffiliated_user_accounts].disable
        GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
        @business.add_owner(@user, actor: @owner)
        assert @business.user_accounts.pluck(:user_id).include?(@user.id)

        @business.remove_owner(@user, actor: @owner)
        refute @business.user_accounts.pluck(:user_id).include?(@user.id)
      end

      test "downgrades the user to unaffiliated if they are not connected to the business in any other way" do
        GitHub.flipper[:unaffiliated_user_accounts].enable
        @business.add_owner(@user, actor: @owner)
        assert @business.user_accounts.pluck(:user_id).include?(@user.id)

        @business.remove_owner(@user, actor: @owner)
        perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
        assert_equal [:unaffiliated], @business.business_user_account_for(@user).business_roles
      end

      test "removes the user from the business if they are connected to the business in another way that doesn't need a business user account" do
        GitHub.flipper[:unaffiliated_user_accounts].disable
        GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
        @business.add_owner(@user, actor: @owner)
        @org1.invite(@user, inviter: @org1.admins.first)
        assert @business.reload.user_accounts.pluck(:user_id).include?(@user.id)

        @business.remove_owner(@user, actor: @owner)
        refute @business.reload.user_accounts.pluck(:user_id).include?(@user.id)
      end

      test "does not remove the user from the business if they are connected to the business in another way that needs a business user account" do
        @business.add_owner(@user, actor: @owner)
        org = create :organization, admin: @user
        @business.add_organization(org)
        assert @business.reload.user_accounts.pluck(:user_id).include?(@user.id)

        @business.remove_owner(@user, actor: @owner)
        assert @business.reload.user_accounts.pluck(:user_id).include?(@user.id)
      end

      test "cancels pending admin invitations where the user is the inviter" do
        @business.add_owner(@user, actor: @owner)
        assert @business.owner?(@user)
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: @user, invitee: create(:user), role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @user, invitee: create(:user), role: :billing_manager
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(inviter: @user)

        @business.remove_owner(@user, actor: @owner)

        refute @business.owner?(@user)
        assert_empty @business.invitations.pending.where(inviter: @user)
      end

      test "cancels pending org invitations where the user is the inviter" do
        @business.add_owner(@user, actor: @owner)
        assert @business.owner?(@user)
        org_invite = create :business_organization_invitation,
          business: @business, inviter: @user
        assert_same_elements \
          [org_invite],
          @business.organization_invitations.pending.where(inviter: @user)

        @business.remove_owner(@user, actor: @owner)

        refute @business.owner?(@user)
        assert_empty @business.organization_invitations.pending.where(inviter: @user)
      end

      test "cancels pending admin invitations where the user is the invitee" do
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: @user, role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: @user, role: :billing_manager
        @business.add_owner(@user, actor: @owner)
        assert @business.owner?(@user)
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(invitee: @user)

        @business.remove_owner(@user, actor: @owner)

        refute @business.owner?(@user)
        assert_empty @business.invitations.pending.where(invitee: @user)
      end

      test "won't remove the last owner" do
        assert_equal 1, @business.owners.count
        assert_raises Business::NoAdminsError do
          @business.remove_owner(@owner, actor: @owner)
        end
        assert @business.owner?(@owner)
      end
    end

    if GitHub.single_business_environment?
      test "demotes the admin from being a site admin when in a single global business env" do
        user = create :staff_admin_user

        GitHub.global_business.add_owner user, actor: nil
        assert GitHub.global_business.owner?(user)
        GitHub.global_business.remove_owner user, actor: nil
        refute GitHub.global_business.owner?(user)
        refute_predicate user, :site_admin?
      end
    else
      test "does not demote site admin when not in a single global business env" do
        user = create :staff_admin_user

        @business.add_owner user, actor: nil
        assert @business.owner?(user)
        @business.remove_owner user, actor: nil
        refute @business.owner?(user)
        assert_predicate user, :site_admin?
      end
    end
  end

  context "#change_admin_role" do
    if GitHub.single_business_environment?
      test "cannot turn an owner into a billing_manager on GHES" do
        admin_to_demote = create :user
        @business.add_owner(admin_to_demote, actor: @owner)

        assert_raises(ArgumentError) do
          @business.change_admin_role(admin_to_demote, new_role: :billing_manager, actor: @owner)
        end
      end
    else
      test "can turn an owner into a billing_manager" do
        admin_to_demote = create :user
        @business.add_owner(admin_to_demote, actor: @owner)
        @business.change_admin_role(admin_to_demote, new_role: :billing_manager, actor: @owner)

        assert @business.billing_manager?(admin_to_demote)
        refute @business.owner?(admin_to_demote)
      end

      test "changing owner to billing_manager cancels pending admin invitations where the user is the inviter" do
        user = create :user
        @business.add_owner(user, actor: @owner)
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: user, invitee: create(:user), role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: user, invitee: create(:user), role: :billing_manager
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(inviter: user)

        @business.change_admin_role(user, new_role: :billing_manager, actor: @owner)

        assert @business.billing_manager?(user)
        refute @business.owner?(user)
        assert_empty @business.invitations.pending.where(inviter: user)
      end

      test "changing owner to billing_manager cancels pending org invitations where the user is the inviter" do
        user = create :user
        @business.add_owner(user, actor: @owner)
        org_invite = create :business_organization_invitation, business: @business, inviter: user
        assert_same_elements \
          [org_invite],
          @business.organization_invitations.pending.where(inviter: user)

        @business.change_admin_role(user, new_role: :billing_manager, actor: @owner)

        assert @business.billing_manager?(user)
        refute @business.owner?(user)
        assert_empty @business.organization_invitations.pending.where(inviter: user)
      end

      test "changing owner to billing_manager cancels pending admin invitations where the user is the invitee" do
        user = create :user
        owner_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: user, role: :owner
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: user, role: :billing_manager
        @business.add_owner(user, actor: @owner)
        assert_same_elements \
          [owner_invite, billing_manager_invite],
          @business.invitations.pending.where(invitee: user)

        @business.change_admin_role(user, new_role: :billing_manager, actor: @owner)

        assert @business.billing_manager?(user)
        refute @business.owner?(user)
        assert_empty @business.invitations.pending.where(invitee: user)
      end

      test "removes billing manager privileges, adds admin privileges when role is OWNER" do
        @business.change_admin_role(@billing_manager, new_role: :owner, actor: @owner)

        refute @business.billing_manager?(@billing_manager)
        assert @business.owner?(@billing_manager)
      end

      test "fails when input is invalid" do
        assert_raises(ArgumentError) do
          @business.change_admin_role(@billing_manager, new_role: :error, actor: @owner)
        end
      end

      test "does nothing if tries to change role to an owner, but admin is already an owner" do
        @business.expects(:add_owner).never
        @business.change_admin_role(@owner, new_role: :owner, actor: @owner)

        assert @business.owner?(@owner.reload)
      end

      test "does nothing if tries to change role to a billing manager, but admin is already a billing manager" do
        @business.billing.expects(:add_manager).never
        @business.change_admin_role(@billing_manager, new_role: :billing_manager, actor: @owner)

        assert @business.billing_manager?(@billing_manager.reload)
      end

      test "raises an error if changing role to owner, but user isn't admin of the business" do
        user = create(:user)
        @business.organizations.first.add_member(user)

        assert_raises(Business::UserNotAnAdminError) do
          @business.change_admin_role(user, new_role: :owner, actor: @owner)
        end
      end

      test "raises an error if changing role to billing manager, but user isn't admin of the business" do
        user = create(:user)
        @business.organizations.first.add_member(user)

        assert_raises(Business::UserNotAnAdminError) do
          @business.change_admin_role(user, new_role: :billing_manager, actor: @owner)
        end
      end

      test "notifies admin by email by default" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "ActionMailer::Base.deliveries.size", +1 do
            @business.change_admin_role(@billing_manager, new_role: :owner, actor: @owner)
          end
        end

        assert @business.owner?(@billing_manager)

        mail = ActionMailer::Base.deliveries.last
        assert_equal "[GitHub] Your role with the #{@business.name} enterprise has changed, and you are now an owner.",
                    mail.subject
        assert_same_elements [@billing_manager.email], mail.to
      end

      test "does not notify admin by email if send_notification is false" do
        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @business.change_admin_role(@billing_manager, new_role: :owner, actor: @owner,
                                      send_notification: false)
        end

        assert @business.owner?(@billing_manager)
      end
    end
  end

  context "::admin_role_for" do
    test "returns the role for owner" do
      assert_equal "Owner", Business.admin_role_for(Business::OWNER_ROLE)
    end

    test "returns the role for billing_manager" do
      assert_equal "Billing Manager", Business.admin_role_for(Business::BILLING_MANAGER_ROLE)
    end
  end

  context "::admin_role_for_message" do
    test "returns role for message for Symbol :owner" do
      assert_equal "an owner", Business.admin_role_for_message(:owner)
    end

    test "returns role for message for Symbol :billing_manager" do
      assert_equal "a billing manager", Business.admin_role_for_message(:billing_manager)
    end

    test "returns role for message for String owner" do
      assert_equal "an owner", Business.admin_role_for_message("owner")
    end

    test "returns role for message for String billing_manager" do
      assert_equal "a billing manager", Business.admin_role_for_message("billing_manager")
    end

    test "returns role for message for a nil role" do
      assert_equal "an administrator", Business.admin_role_for_message(nil)
    end
  end

  context "#send_admin_added_email_notification" do
    test "notifies an admin by email using business admin template that they have been added to a non-EMU enterprise" do
      BusinessMailer.expects(:added_as_business_admin).once.with(
        @business,
        :owner,
        @owner,
      ).returns(stub(deliver_later: nil))

      @business.send_admin_added_email_notification(role: :owner, admin: @owner)
    end
  end

  context "logging admin checks" do
    test "#permit? logs admin info", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @owner.id,
        "gh.actor.type": @owner.class.name,
        "gh.method": "permit?",
      }

      assert_logged(**expected_log) do
        assert @business.permit?(@owner, :admin)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:permit?"]
      end
    end

    test "#async_permit? logs admin info", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @owner.id,
        "gh.actor.type": @owner.class.name,
        "gh.method": "async_permit?"
      }

      assert_logged(**expected_log) do
        assert @business.async_permit?(@owner, :admin)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:async_permit?"]
      end
    end

    test "#permit? logs info for non-admins", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @member1.id,
        "gh.actor.type": @member1.class.name,
        "gh.method": "permit?"
      }

      assert_logged(**expected_log) do
        refute @business.permit?(@member1, :admin)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:permit?"]
      end
    end

    test "#adminable_by? logs admin info", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @owner.id,
        "gh.actor.type": @owner.class.name,
        "gh.method": "permit?"
      }

      assert_logged(**expected_log) do
        assert @business.adminable_by?(@owner)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:permit?"]
      end
    end

    test "#owner? logs admin info", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @owner.id,
        "gh.actor.type": @owner.class.name,
        "gh.method": "permit?"
      }

      assert_logged(**expected_log) do
        assert @business.owner?(@owner)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:permit?"]
      end
    end

    test "resource ablity checks log admin info for users", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
        "gh.business.id": @business.id,
        "gh.actor.id": @owner.id,
        "gh.actor.type": @owner.class.name,
        "gh.method": "async_permit?"
      }

      assert_logged(**expected_log) do
        assert @business.resources.enterprise_administration.readable_by?(@owner)
        assert_dogstats_increment 1, "business_admin_check.executed", tags: ["method:async_permit?"]
      end
    end

    test "resource ability check does not log admin info for bots", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
      }
      bot = create(:integration).bot

      refute_logged(**expected_log) do
        refute @business.resources.enterprise_administration.readable_by?(bot)
        refute_dogstats_increment "business_admin_check.executed"
      end
    end

    test "#permit? logs nothing when ff is disabled", feature_disabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
      }

      refute_logged(**expected_log) do
        assert @business.permit?(@owner, :admin)
        refute_dogstats_increment "business_admin_check.executed"
      end
    end

    test "#async_permit? logs nothing when ff is disabled", feature_disabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
      }

      refute_logged(**expected_log) do
        assert @business.async_permit?(@owner, :admin)
        refute_dogstats_increment "business_admin_check.executed"
      end
    end

    test "#owners does not log admin info", feature_enabled: :log_business_admin_check do
      expected_log = {
        Body: "Business admin check executed",
      }

      refute_logged(**expected_log) do
        assert @business.owners.include?(@owner)
        refute_dogstats_increment "business_admin_check.executed"
      end
    end
  end
end
