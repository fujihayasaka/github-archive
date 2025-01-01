# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessConfigurationEntriesTest < GitHub::TestCase
  fixtures do
    @business = create :business
  end

  test "inherit from GitHub" do
    assert_equal GitHub, @business.configuration_owner
  end

  test "can be set and read" do
    @business.allow_private_repository_forking(actor: @business.owners.first)
    assert @business.allow_private_repository_forking?
  end

  test "includes audit log information" do
    events = subscribe("config_entry.create")
    @business.allow_private_repository_forking(actor: @business.owners.first)
    assert_equal 1, events.size

    event = events.first
    assert_equal "Business", event.payload[:target_type]
    assert_equal @business.slug, event.payload[:business]
    assert_equal @business.id, event.payload[:business_id]
  end

  test "set_default_emu_repo_collab_policy called on create hook", skip_enterprise: true do
    business = create(:business, :enterprise_managed)
    assert business.enterprise_admins_only_can_invite_outside_collaborators?
  end

  test "set_default_emu_repo_collab_policy does nothing if not EMU business" do
    @business.set_default_emu_repo_collab_policy
    refute @business.enterprise_admins_only_can_invite_outside_collaborators?
  end

  test "set_default_emu_repo_collab_policy no-ops if a policy is already set", skip_enterprise: true do
    business = create(:business, :enterprise_managed)
    business.disallow_members_can_invite_outside_collaborators(actor: User.ghost)
    refute business.enterprise_admins_only_can_invite_outside_collaborators?
    business.set_default_emu_repo_collab_policy
    refute business.enterprise_admins_only_can_invite_outside_collaborators?
  end
end
