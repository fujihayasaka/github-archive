# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationFeatureFlagsDependencyTest < GitHub::TestCase
  context "#flipper_actor_names" do
    test "from_flipper_actor_name" do
      organization = create :organization
      # assert that getting the organization from the flipper actor name returns the same organization
      assert_equal organization, Organization.from_flipper_actor_name(organization.flipper_actor_name)
      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal organization.flipper_id, organization.flipper_actor_name
      # assert that that flipper actor name is the display_login
      assert_equal organization.display_login, organization.flipper_actor_name
    end
  end
end
