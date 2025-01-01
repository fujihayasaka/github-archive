# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventOrganizationEventTest < GitHub::TestCase
  include HookEventTestHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user   = create(:user)
    @actor  = create(:user)
    @owner  = create(:user)
    @org    = create(:organization, admin: @owner)

    @event = Hook::Event::OrganizationEvent.new(
      action: :created,
      organization_id: @org.id,
      actor_id: @actor.id,
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::OrganizationEvent, :action, :organization_id
  end

  context "#organization" do
    test "returns the specified organization" do
      assert_equal @org, @event.organization
    end
  end

  context "#user" do
    test "raises an exception if the user attribute is required but not specified" do
      event = Hook::Event::OrganizationEvent.new(
        action: :member_added,
        organization_id: @org.id,
        user_id: nil,
        actor_id: @actor.id,
      )

      assert_raises(Hook::Event::MissingRequiredAttribute) { event.user }
    end

    test "returns the specified user being modified" do
      @event = Hook::Event::OrganizationEvent.new(
          action: :member_added,
          organization_id: @org.id,
          user_id: @user.id,
          actor_id: @actor.id,
      )
      assert_equal @user, @event.user
    end
  end

  context "#actor" do
    test "returns the user who initiated the membership change if one exists" do
      assert_equal @actor, @event.actor
    end

    test "falls back to the Ghost user if no actor is present" do
      event = Hook::Event::OrganizationEvent.new(
        action: :member_added,
        organization_id: @org.id,
        user_id: @user.id,
        actor_id: nil,
      )

      assert_equal User.ghost, event.actor
    end
  end

  context "#target_organization" do
    test "returns the organization in question" do
      assert_equal @org, @event.target_organization
    end
  end

  context "#target_business" do
    test "for the deleted action, returns the Business associated with the Organization's SoftDeletedOrganization" do
      business = create :business, organizations: [@org]
      actor = @org.admins.first
      @org.reload.soft_delete!(actor)

      assert SoftDeletedOrganization.find_by(organization: @org, business: business)
      assert_nil @org.reload.business

      event = Hook::Event::OrganizationEvent.new(
        action: :deleted,
        organization_id: @org.id,
        actor_id: actor.id,
      )

      assert_equal business, event.target_business
    end
  end

  context "#deliverable?" do
    test "returns false if the organization is not found" do
      event = Hook::Event::OrganizationEvent.new(
        action: :created,
        organization_id: -1,
        user_id: @user.id,
        actor_id: @actor.id,
      )

      refute_predicate event, :deliverable?
    end

    test "returns true if the organization and user are present" do
      event = Hook::Event::OrganizationEvent.new(
        action: :member_added,
        organization_id: @org.id,
        user_id: @user.id,
        actor_id: @actor.id,
      )

      assert_predicate event, :deliverable?
    end

    test "returns true if the organization and invitation are present" do
      invitation = @org.invite(@user, inviter: @owner)

      event = Hook::Event::OrganizationEvent.new(
        action: :member_invited,
        organization_id: @org.id,
        invitation_id: invitation.id,
        actor_id: @actor.id,
      )

      assert_predicate event, :deliverable?
    end

    test "returns true without invitation or user" do
      event = Hook::Event::OrganizationEvent.new(
          action: :created,
          organization_id: @org.id,
          actor_id: @actor.id,
      )
      assert_predicate event, :deliverable?
    end
  end

  context ".description" do
    test "returns the correct description when on dotcom and extended_org_hooks_enabled is false" do
      begin
        GitHub.stubs(:dotcom_request?).returns(true)
        GitHub.stubs(:extended_org_hooks_enabled?).returns(false)
        assert_equal "Organization deleted, renamed, member invited, member added, or member removed.",
          Hook::Event::OrganizationEvent.description
      ensure
        GitHub.unstub(:dotcom_request?)
        GitHub.unstub(:extended_org_hooks_enabled?)
      end
    end

    test "returns the correct description when on enterprise and extended_org_hooks_enabled is true" do
      begin
        GitHub.stubs(:dotcom_request?).returns(false)
        GitHub.stubs(:extended_org_hooks_enabled?).returns(true)
        assert_equal "Organization created, deleted, renamed, member invited, member added, or member removed.",
          Hook::Event::OrganizationEvent.description
      ensure
        GitHub.unstub(:extended_org_hooks_enabled)
        GitHub.unstub(:dotcom_request?)
      end
    end

    test "returns the correct description when on enterprise and extended_org_hooks_enabled is false" do
      begin
        GitHub.stubs(:dotcom_request?).returns(false)
        GitHub.stubs(:extended_org_hooks_enabled?).returns(false)
        assert_equal "Organization renamed, member invited, member added, or member removed.",
          Hook::Event::OrganizationEvent.description
      ensure
        GitHub.unstub(:extended_org_hooks_enabled)
        GitHub.unstub(:dotcom_request?)
      end
    end
  end
end
