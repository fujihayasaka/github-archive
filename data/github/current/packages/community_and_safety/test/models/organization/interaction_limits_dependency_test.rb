# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationInteractionLimitsDependencyTest < GitHub::TestCase
  fixtures do
    @org    = create(:organization)
    @owner  = @org.admin
    @member = create(:user)
    @rando  = create(:user)

    @org.add_member(@member)
  end

  context "#can_read_interaction_limits?" do
    test "true for org owners" do
      assert @org.can_read_interaction_limits?(@owner)
      assert @org.async_can_read_interaction_limits?(@owner).sync
    end

    test "true for installation with read access to org administration" do
      installation = make_integration_installation(target: @org, permissions: {
        "organization_administration" => :read,
      })

      assert @org.can_read_interaction_limits?(installation)
      assert @org.async_can_read_interaction_limits?(installation).sync
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "true for org moderators" do
        moderator = create(:user)
        @org.add_member(moderator)
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(moderator, actor: @owner)
        assert @org.moderator?(moderator)

        assert @org.can_read_interaction_limits?(moderator)
        assert @org.async_can_read_interaction_limits?(moderator).sync
      end
    end

    test "false for installation without read access to org administration" do
      installation = make_integration_installation(target: @org, permissions: {
        "members" => :read,
      })

      refute @org.can_read_interaction_limits?(installation)
      refute @org.async_can_read_interaction_limits?(installation).sync
    end

    test "false for org member" do
      refute @org.can_read_interaction_limits?(@member)
      refute @org.async_can_read_interaction_limits?(@member).sync
    end

    test "false for random user" do
      refute @org.can_read_interaction_limits?(@rando)
      refute @org.async_can_read_interaction_limits?(@rando).sync
    end
  end

  context "#can_set_interaction_limits?" do
    test "true for org owners" do
      assert @org.can_set_interaction_limits?(@owner)
      assert @org.async_can_set_interaction_limits?(@owner).sync
    end

    test "true for installation with write access to org administration" do
      installation = make_integration_installation(target: @org, permissions: {
        "organization_administration" => :write,
      })

      assert @org.can_read_interaction_limits?(installation)
      assert @org.async_can_set_interaction_limits?(installation).sync
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "true for org moderators" do
        moderator = create(:user)
        @org.add_member(moderator)
        moderation = Organization::Moderation.new(@org)
        moderation.add_moderator(moderator, actor: @owner)
        assert @org.moderator?(moderator)

        assert @org.can_set_interaction_limits?(moderator)
        assert @org.async_can_set_interaction_limits?(moderator).sync
      end
    end

    test "false for installation without write access to org administration" do
      installation = make_integration_installation(target: @org, permissions: {
        "organization_administration" => :read,
      })

      refute @org.can_set_interaction_limits?(installation)
      refute @org.async_can_set_interaction_limits?(installation).sync
    end

    test "false for org member" do
      refute @org.can_set_interaction_limits?(@member)
      refute @org.async_can_set_interaction_limits?(@member).sync
    end

    test "false for random user" do
      refute @org.can_set_interaction_limits?(@rando)
      refute @org.async_can_set_interaction_limits?(@rando).sync
    end
  end
end
