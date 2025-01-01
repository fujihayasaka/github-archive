# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessBillingManagementTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @business = create :business, owners: [@owner]
    @user = create(:user)
  end

  setup do
    @billing = Business::BillingManagement.new(@business)
  end

  context "#add_manager" do
    test "raises InvalidAdminStateError if user is suspended" do
      @user.suspend "Reasons"
      assert_raises Business::InvalidAdminStateError do
        @billing.add_manager @user, actor: @business.owners.first
      end
    end

    test "raises InvalidAdminStateError if user is deceased" do
      @user.mark_deceased
      assert_raises Business::InvalidAdminStateError do
        @billing.add_manager @user, actor: @business.owners.first
      end
    end

    test "grants a user write access to a business's billing management" do
      refute @billing.manager?(@user)
      @billing.add_manager(@user, actor: @business.owners.first)
      assert @billing.manager?(@user)
    end

    test "creates a user account for the billing manager if it doesn't exists" do
      GitHub.stubs(:single_business_environment?).returns(false)
      refute @business.user_accounts.pluck(:user_id).include?(@user.id)
      @billing.add_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)
    end

    test "does not create another user account if it already exists" do
      GitHub.stubs(:single_business_environment?).returns(false)
      refute @business.user_accounts.pluck(:user_id).include?(@user.id)

      org = create :organization, admin: @user
      perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { @business.add_organization(org) }
      assert @business.reload.user_accounts.pluck(:user_id).include?(@user.id)
      assert_equal 1, @business.user_accounts.pluck(:user_id).count(@user.id)

      @billing.add_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)
      assert_equal 1, @business.user_accounts.pluck(:user_id).count(@user.id)
    end

    test "doesn't add the user to the business for single_business_environment" do
      GitHub.stubs(:single_business_environment?).returns(true)
      Business.delete_all
      business = create :business, owners: [@owner]
      @billing.add_manager(@user, actor: @owner)
      assert_equal 0, business.user_accounts.count
    end

    test "instruments adding a billing manager" do
      events = subscribe "business.add_billing_manager"
      @billing.add_manager(@user, actor: @business.owners.first)

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        actor: @business.owners.first.login,
        actor_id: @business.owners.first.id,
        business: @business.slug,
        business_id: @business.id,
        name: @business.name,
      }

      assert event = events.pop, "a business.add_billing_manager event was expected"
      assert_equal "business.add_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "hides staff information when adding a billing manager", skip_enterprise: true do
      staff = create :staff_admin_user
      events = subscribe "business.add_billing_manager"
      @billing.add_manager(@user, actor: staff, staff_action: true)

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        staff_actor: staff.display_login,
        staff_actor_id: staff.id,
        # avoid adding a dependency to User
        actor:  "github-staff",
        business: @business.slug,
        business_id: @business.id,
        name: @business.name,
      }

      assert event = events.pop, "a business.add_billing_manager event was expected"
      assert_equal "business.add_billing_manager", event.name
      assert_subset_hash expected_payload, event.payload
      refute_equal event.payload[:actor_id], @user.id
    end

    test "sends a notification email to the billing manager if send_notification is true" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", 1 do
          @billing.add_manager(@user, actor: @business.owners.first, send_notification: true)
        end
      end

      mail = ActionMailer::Base.deliveries.first
      assert_same_elements [@user.email], mail.to
    end

    test "does not send a notification email by default" do
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @billing.add_manager(@user, actor: @business.owners.first)
      end
    end
  end

  context "#remove_manager" do
    test "revokes a user's access to a business's billing" do
      @billing.add_manager(@user, actor: @business.owners.first)
      assert @billing.manager?(@user)

      @billing.remove_manager(@user, actor: @business.owners.first)
      refute @billing.manager?(@user)
    end

    unless GitHub.bypass_business_member_invites_enabled?
      test "cancels pending invitations where the user is the inviter" do
        @billing.add_manager(@user, actor: @owner)
        assert @billing.manager?(@user)
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @user, invitee: create(:user), role: :billing_manager
        assert_same_elements \
          [billing_manager_invite],
          @business.invitations.pending.where(inviter: @user)

        @billing.remove_manager(@user, actor: @owner)

        refute @billing.manager?(@user)
        assert_empty @business.invitations.pending.where(inviter: @user)
      end

      test "cancels pending invitations where the user is the invitee" do
        billing_manager_invite = create :business_administrator_invitation,
          business: @business, inviter: @owner, invitee: @user, role: :billing_manager
        @billing.add_manager(@user, actor: @owner)
        assert @billing.manager?(@user)
        assert_same_elements \
          [billing_manager_invite],
          @business.invitations.pending.where(invitee: @user)

        @billing.remove_manager(@user, actor: @owner)

        refute @billing.manager?(@user)
        assert_empty @business.invitations.pending.where(inviter: @user)
      end
    end

    test "removes the user from the business if they are not connected to the business in any other way" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      GitHub.stubs(:single_business_environment?).returns(false)
      @billing.add_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)

      @billing.remove_manager(@user, actor: @owner)
      refute @business.user_accounts.pluck(:user_id).include?(@user.id)
    end

    test "downgrades the user to unaffiliated if they are not connected to the business in any other way" do
      enable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      GitHub.stubs(:single_business_environment?).returns(false)
      @billing.add_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)

      @billing.remove_manager(@user, actor: @owner)
      perform_enqueued_jobs only: BusinessUserAccountUpdateAttributesJob
      assert_equal [:unaffiliated], @business.business_user_account_for(@user).business_roles
    end

    test "does not remove the user from the business if they are connected to the business in another way" do
      disable_feature_flag(:unaffiliated_user_accounts)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb)
      GitHub.stubs(:single_business_environment?).returns(false)
      @business.add_owner(@user, actor: @owner)
      org = create :organization, admin: @user
      @business.add_organization(org)
      @billing.add_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)

      @billing.remove_manager(@user, actor: @owner)
      assert @business.user_accounts.pluck(:user_id).include?(@user.id)
    end

    test "doesn't remove the user from the business for single_business_environment" do
      GitHub.stubs(:single_business_environment?).returns(true)
      Business.delete_all
      business = create :business, owners: [@owner]
      @billing.add_manager(@user, actor: @owner)
      assert_equal 0, business.user_accounts.count

      @billing.remove_manager(@user, actor: @owner)
      assert_equal 0, business.user_accounts.count
    end

    test "doesn't blow up when trying to revoke access if access doesn't exist" do
      refute @billing.manager?(@user)
      @billing.remove_manager(@user, actor: @business.owners.first)
    end

    test "instruments removing a billing manager" do
      events = subscribe "business.remove_billing_manager"
      @billing.add_manager(@user, actor: @business.owners.first)
      assert @billing.manager?(@user),
        "Setup failed: Expected #{@user} to be a billing manager"

      @billing.remove_manager(@user, actor: @business.owners.first)

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        actor: @business.owners.first.login,
        actor_id: @business.owners.first.id,
        business: @business.slug,
        business_id: @business.id,
        name: @business.name,
        reason: nil,
      }

      assert event = events.pop, "a business.remove_billing_manager event was expected"
      assert_equal "business.remove_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "sends a notification email to the billing manager by default" do
      @billing.add_manager(@user, actor: @business.owners.first)

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", 1 do
          @billing.remove_manager(@user, actor: @business.owners.first)
        end
      end

      mail = ActionMailer::Base.deliveries.first
      assert_same_elements [@user.email], mail.to
    end

    test "does not send a notification email if send_notification is false" do
      @billing.add_manager(@user, actor: @business.owners.first)

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @billing.remove_manager(@user, actor: @business.owners.first, send_notification: false)
      end
    end
  end
end
