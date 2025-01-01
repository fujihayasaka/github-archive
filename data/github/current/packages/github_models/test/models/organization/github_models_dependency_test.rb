# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::GitHubModelsDependencyTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
  end

  context "#enable_models_access" do
    test "emits audit log event" do
      events = subscribe("org.github_models_enabled")

      assert_difference("events.size") do
        assert @org.enable_models_access(@org_admin)
      end

      assert_predicate @org, :models_access_enabled?
      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        actor: @org_admin.login,
        actor_id: @org_admin.id,
        org: @org.login,
        org_id: @org.id,
      }, event.payload)
    end
  end

  context "#disable_models_access" do
    test "emits audit log event" do
      assert @org.enable_models_access(@org_admin, instrument: false)
      events = subscribe("org.github_models_disabled")

      assert_difference("events.size") do
        assert @org.disable_models_access(@org_admin)
      end

      refute_predicate @org, :models_access_enabled?
      refute_nil event = events.pop, "a new audit log event was expected"
      assert_subset_hash({
        actor: @org_admin.login,
        actor_id: @org_admin.id,
        org: @org.login,
        org_id: @org.id,
      }, event.payload)
    end
  end
end
