# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationBillingManagementTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org       = create(:organization, admin: @org_admin)
    @user      = create(:user)
  end

  setup do
    @billing = Organization::BillingManagement.new(@org)
  end

  context "#manager?" do
    test "false if the user does not have :write access" do
      refute @billing.manager?(@user)
      refute @billing.async_manager?(@user).sync
    end

    test "true if the user has :write access" do
      @billing.add_manager(@user, actor: @org_admin)
      assert @billing.manager?(@user)
      assert @billing.async_manager?(@user).sync
    end
  end

  context "#remove_manager" do
    test "revokes access a user's access to an organization's billing" do
      @billing.add_manager(@user, actor: @org_admin)
      assert @billing.manager?(@user)

      @billing.remove_manager(@user, actor: @org_admin)
      refute @billing.manager?(@user)
    end

    test "doesn't explode when trying to revoke access if access doesn't exist" do
      refute @billing.manager?(@user)
      @billing.remove_manager(@user, actor: @org_admin)
    end

    test "instruments the removal of the billing manager" do
      events = subscribe "org.remove_billing_manager"
      reason = :two_factor_requirement_non_compliance
      @billing.add_manager(@user, actor: @org.admin)
      assert @billing.manager?(@user),
        "Setup failed: Expected #{@user} to be a billing manager"

      @billing.remove_manager(@user, actor: @org_admin, reason: reason)

      expected_payload = {
        user: "#{@user}",
        user_id: @user.id,
        org_id: @org.id,
        org: "#{@org}",
        actor: "#{@org_admin}",
        actor_id: @org_admin.id,
        reason: reason,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "org.remove_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end

    test "unlinks billing info if linked billing manager is removed from the org" do
      billing_manager = create(:user, :with_trade_screening_record)
      org = create(:organization)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      billing_manager.link_trade_screening_record_to_org(organization: org)
      assert org.billing_manageable_by?(billing_manager)
      assert_predicate org, :has_linked_trade_screening_record?

      org.billing.remove_manager(billing_manager, actor: org.admins.first)
      refute org.billing_manageable_by?(billing_manager)
      refute_predicate org, :has_linked_trade_screening_record?
    end

    test "doesn't unlink billing info if billing manager is removed from the org and doesn't own the linked billing info" do
      new_admin = create(:user, :with_trade_screening_record)
      billing_manager = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: new_admin)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      assert org.reload.members.include?(new_admin)
      assert org.billing_manageable_by?(billing_manager)
      new_admin.link_trade_screening_record_to_org(organization: org)

      org.billing.remove_manager(billing_manager, actor: org.admins.first)
      refute org.billing_manageable_by?(billing_manager)
      assert_predicate org, :has_linked_trade_screening_record?
    end
  end

  context "#add_manager" do
    test "grants a user write access to an organization's billing management" do
      refute @billing.manager?(@user)
      @billing.add_manager(@user, actor: @org_admin)
      assert @billing.manager?(@user)
    end

    test "does not allow a non-user to be added as a billing manager" do
      other_org = create(:organization)
      assert_raises RuntimeError do
        @billing.add_manager(other_org, actor: @org_admin)
      end
    end

    test "instruments the addition of new billing manager" do
      events = subscribe "org.add_billing_manager"
      @billing.add_manager(@user, actor: @org_admin)

      expected_payload = {
        user: "#{@user}",
        user_id: @user.id,
        org_id: @org.id,
        org: "#{@org}",
        actor: "#{@org_admin}",
        actor_id: @org_admin.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "org.add_billing_manager", event.name
      assert_equal expected_payload, event.payload
    end
  end

  test "removes billing management abilities when an organization is destroyed" do
    @billing.add_manager(@user, actor: @org_admin)
    @org.destroy
    assert_equal [], @billing.members
  end
end
