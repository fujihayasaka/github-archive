# typed: true
# frozen_string_literal: true

require "test_helper"

class EmuBusinessTest < GitHub::TestCase
  fixtures do
    @default_managed_business = create :business
    @owner = create(:emu, :owner)
    @enterprise = @owner.enterprise_managed_business
    @first_admin = @enterprise.find_first_emu_owner
    @member = create(:emu, business: @enterprise)
    @guest_collaborator = create(:emu, :guest_collaborator, business: @enterprise)

    @org = create :organization, business: @enterprise, admin: @owner
  end

  test "can enable audit log ip disclosure returns true for emu or non-emu business" do
    refute @default_managed_business.enterprise_managed_user_enabled?
    assert @default_managed_business.can_enable_audit_log_ip_disclosure?
  end

  test "raises InvalidAdminStateError when business is an EMU" do
    assert_raises Business::InvalidAdminStateError  do
      @enterprise.invite_admin(user: @member, inviter: @owner, role: :billing_manager)
    end

    assert_raises Business::InvalidAdminStateError do
      @enterprise.invite_admin(user: @member, inviter: @owner, role: :owner)
    end
  end

  test "does not raises InvalidAdminStateError when business is an EMU and invite from stafftools" do
    invitation = @enterprise.invite_admin(user: @member, inviter: @owner, role: :billing_manager, stafftools_invite: true)
    assert_equal @enterprise, invitation.business
    assert_equal @member, invitation.invitee

    invitation = @enterprise.invite_admin(user: @member, inviter: @owner, role: :owner, stafftools_invite: true)
    assert_equal @enterprise, invitation.business
    assert_equal @member, invitation.invitee
  end

  test "does not remove business user account if the user is enterprise managed" do
    assert @enterprise.reload.user_accounts.pluck(:user_id).include?(@owner.id)
    assert @enterprise.owner?(@owner)

    @enterprise.remove_owner(@owner, actor: nil)

    assert @enterprise.reload.user_accounts.pluck(:user_id).include?(@owner.id)
    refute @enterprise.owner?(@owner)
  end

  test "notifies the first emu admin user by email using emu first business admin template that they have been added to an EMU enterprise" do
    EnterpriseManagedUserMailer.expects(:added_as_first_emu_business_admin).once.with(
      @enterprise,
      :owner,
      @first_admin,
    ).returns(stub(deliver_later: nil))

    @enterprise.send_admin_added_email_notification(role: :owner, admin: @first_admin)
  end

  test "notifies the IdP backed emu admin by email using business admin template that they have been added to an EMU enterprise" do
    BusinessMailer.expects(:added_as_business_admin).once.with(
      @enterprise,
      :owner,
      @owner,
    ).returns(stub(deliver_later: nil))

    @enterprise.send_admin_added_email_notification(role: :owner, admin: @owner)
  end

  test "raises Business::CannotRemoveOrganizationError when removing organization from an EMU business" do
    assert_no_difference ["Business::OrganizationMembership.count"] do
      assert_raises Business::CannotRemoveOrganizationError do
        @enterprise.remove_organization @org
      end
    end
  end

  test "returns false for an EMU business" do
    refute @enterprise.actor_can_remove_organizations?(actor: @owner)
  end

  test "delete first emu owner when enterprise is deleted" do
    refute_nil User.find(@first_admin.id)
    refute_nil Business.find(@enterprise.id)

    perform_enqueued_jobs(only: UserDeleteJob) do
      @enterprise.destroy
    end

    assert_raises ActiveRecord::RecordNotFound do
      User.find(@first_admin.id)
    end

    assert_raises ActiveRecord::RecordNotFound do
      Business.find(@enterprise.id)
    end
  end

  test "guest collaborators can see all orgs in the enterprise that they are a member of by default" do
    org2 = create :organization, business: @enterprise, admin: @first_admin

    assert_same_elements [], @enterprise.filtered_organizations(viewer: @guest_collaborator).to_a

    @org.add_member @guest_collaborator

    assert_same_elements [@org], @enterprise.filtered_organizations(viewer: @guest_collaborator).to_a
  end

  test "returns external_members" do
    assert_same_elements [@owner, @member, @guest_collaborator], @enterprise.external_members
  end

  test "raises Business::SoftDeletionUnsupportedError when soft-deleting a EMU business" do
    GitHub.flipper[:soft_delete_organization].disable
    assert_raises Business::SoftDeletionUnsupportedError do
      @enterprise.soft_delete!
    end
  end
end unless GitHub.single_business_environment?
