# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessMemberInviteStatusTest < GitHub::TestCase
  fixtures do
    @business = create :business
    @admin = @business.owners.first
    @billing_manager = create :user
    @business.billing.add_manager @billing_manager, actor: @admin
    @invitee = create :user, login: "invitee"
    @invitee.emails.each(&:verify!)
  end

  setup do
    GitHub.stubs(:single_business_environment?).returns(true)
  end

  context "#errors" do
    test "empty when unassociated invitee is invited as an admin" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      assert_empty status.errors
    end

    test "empty when unassociated invitee is invited as a billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      assert_empty status.errors
    end

    test "empty when unassociated invitee is invited as a billing manager by another billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :billing_manager)
      assert_empty status.errors
    end

    test "includes :already_business_admin when invitee is already an admin" do
      @business.add_owner @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      assert_same_elements [:already_business_admin], status.errors
    end

    test "includes :already_business_billing_manager when invitee is already a billing manager" do
      @business.billing.add_manager @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      assert_same_elements [:already_business_billing_manager], status.errors
    end

    test "includes :invitee_is_not_a_user when invitee is not a User" do
      invitee = create :organization
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :owner)
      assert_same_elements [:invitee_is_not_a_user], status.errors
    end

    test "includes :invitee_has_invalid_state when invitee is suspended" do
      invitee = create :suspended_user
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :owner)
      assert_same_elements [:invitee_has_invalid_state], status.errors
    end

    test "includes :invitee_has_invalid_state when invitee is deceased" do
      invitee = create :user
      invitee.mark_deceased
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :owner)
      assert_same_elements [:invitee_has_invalid_state], status.errors
    end

    test "includes :invitee_has_invalid_state_member when invitee is suspended and role is unaffiliated" do
      invitee = create :suspended_user
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :unaffiliated)
      assert_same_elements [:invitee_has_invalid_state_member], status.errors
    end

    test "includes :invitee_has_invalid_state_member when invitee is deceased and role is unaffiliated" do
      invitee = create :user
      invitee.mark_deceased
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :unaffiliated)
      assert_same_elements [:invitee_has_invalid_state_member], status.errors
    end

    test "includes :insufficient_inviter_permissions when inviter is not an admin" do
      inviter = create :user
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: inviter, role: :owner)
      assert_same_elements [:insufficient_inviter_permissions], status.errors
    end

    test "includes :insufficient_inviter_permissions when inviter is billing manager and owner invitation" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :owner)
      assert_same_elements [:insufficient_inviter_permissions], status.errors
    end

    test "includes :invitee_and_email_provided when both invitee and email provided" do
      status = Business::MemberInviteStatus.new(
        @business, @invitee, inviter: @admin, role: :owner, email: "hello@example.com")
      assert_same_elements [:invitee_and_email_provided], status.errors
    end

    test "includes :invitee_or_email_required when neither invitee nor email provided" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner)
      assert_same_elements [:invitee_or_email_required], status.errors
    end

    test "includes :invalid_email when email is invalid" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner, email: "invalid email")
      assert_same_elements [:invalid_email], status.errors
    end
  end

  context "#valid?" do
    test "true when unassociated invitee is invited as an admin" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      assert_predicate status, :valid?
    end

    test "true when unassociated invitee is invited as a billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      assert_predicate status, :valid?
    end

    test "true when unassociated invitee is invited as a billing manager by another billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :billing_manager)
      assert_predicate status, :valid?
    end

    test "false when invitee is already an admin" do
      @business.add_owner @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      refute_predicate status, :valid?
    end

    test "false when invitee is already a billing manager" do
      @business.billing.add_manager @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      refute_predicate status, :valid?
    end

    test "false when inviter is not a User" do
      invitee = create :organization
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :owner)
      refute_predicate status, :valid?
    end

    test "false when inviter is not an admin" do
      inviter = create :user
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: inviter, role: :owner)
      refute_predicate status, :valid?
    end

    test "false when inviter is billing manager and owner invitation" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :owner)
      refute_predicate status, :valid?
    end

    test "false when both invitee and email provided" do
      status = Business::MemberInviteStatus.new(
        @business, @invitee, inviter: @admin, role: :owner, email: "hello@example.com")
      refute_predicate status, :valid?
    end

    test "false when neither invitee nor email provided" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner)
      refute_predicate status, :valid?
    end

    test "false when email is invalid" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner, email: "invalid email")
      refute_predicate status, :valid?
    end
  end

  context "#validate!" do
    test "true when unassociated invitee is invited as an admin" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      assert_predicate status, :validate!
    end

    test "true when inviter has manage enterprise invitations permissions" do
      member = create :user
      @business.add_user_accounts([member.id])
      Business.any_instance.stubs(:actor_can_manage_invitations?).with(member).returns(true)
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: member, role: :owner)
      assert_predicate status, :validate!
    end

    test "true when unassociated invitee is invited as a billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      assert_predicate status, :validate!
    end

    test "true when unassociated invitee is invited as a billing manager by another billing manager" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :billing_manager)
      assert_predicate status, :validate!
    end

    test "raises BusinessAdministratorInvitation::InvalidError when invitee is already an admin" do
      @business.add_owner @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :owner)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "raises BusinessAdministratorInvitation::InvalidError when invitee is already a billing manager" do
      @business.billing.add_manager @invitee, actor: @admin
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @admin, role: :billing_manager)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "raises BusinessAdministratorInvitation::InvalidError when inviter is not a User" do
      invitee = create :organization
      status = Business::MemberInviteStatus.new(@business, invitee, inviter: @admin, role: :owner)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "raises BusinessAdministratorInvitation::InvalidError when inviter is not an admin" do
      inviter = create :user
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: inviter, role: :owner)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "raises BusinessAdministratorInvitation::InvalidError when inviter is billing manager and owner invitation" do
      status = Business::MemberInviteStatus.new(@business, @invitee, inviter: @billing_manager, role: :owner)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "includes :invitee_and_email_provided when both invitee and email provided" do
      status = Business::MemberInviteStatus.new(
        @business, @invitee, inviter: @admin, role: :owner, email: "hello@example.com")
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "includes :invitee_or_email_required when neither invitee nor email provided" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner)
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end

    test "includes :invalid_email when email is invalid" do
      status = Business::MemberInviteStatus.new(
        @business, nil, inviter: @admin, role: :owner, email: "invalid email")
      assert_raises(BusinessAdministratorInvitation::InvalidError) { status.validate! }
    end
  end
end
