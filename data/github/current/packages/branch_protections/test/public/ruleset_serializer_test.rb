# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::RulesetSerializerTest < GitHub::TestCase

  fixtures do
    @staff_user = create(:staff_admin_user)
    @owner      = create(:user)
    @org        = create(:organization, admin: @owner)
    @repo       = create(:repository, owner: @org)
    @ruleset    = create(:repository_ruleset, :example_ruleset, :repo_admin_bypass, source: @repo)
  end

  context "#ruleset_hash" do
    test "return ruleset as hash" do
      ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset)
      assert ruleset_hash.is_a?(Hash)
    end

    test "org admins are shown as bypass actors and not in the bypass prohibited column" do
      @ruleset.bypass_mode = :org_bypass_any
      @ruleset.save

      ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset, user: @owner)
      refute ruleset_hash[:bypass_mode]
      assert ruleset_hash[:bypass_actors]
      assert_includes ruleset_hash[:bypass_actors].map { |ba| ba[:actor_type] }, "OrganizationAdmin"
    end

    context "test bypass actors rendering" do
      test "by default does not show bypass actors" do
        ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset)
        refute ruleset_hash[:bypass_actors]
      end

      test "shows bypass actors when a user has the appropriate permissions" do
        ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset, user: @owner)
        assert ruleset_hash[:bypass_actors]
      end

      test "does not show bypass actors when a user does not have appropriate permissions" do
        ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset, user: @staff_user)
        refute ruleset_hash[:bypass_actors]
      end

      test "shows bypass actors to staff when viewed in stafftools" do
        ruleset_hash = RulesEngine::RulesetSerializer.ruleset_hash(@ruleset, user: @staff_user, is_stafftools: true)
        assert ruleset_hash[:bypass_actors]
      end
    end
  end if GitHub.flipper[:rules_history].enabled?

  context "#history_to_html_string" do
    context "formatting" do
      test "serialize ruleset in a format for html" do
        serialized = RulesEngine::RulesetSerializer.history_to_html_string(@ruleset.histories.first)
        assert serialized.is_a?(String)
        assert_includes serialized, GitHub::HTMLSafeString::BR
        assert_includes serialized, GitHub::HTMLSafeString::NBSP
        assert_includes serialized, "name"
      end

      test "return nil for ruleset with empty state" do
        empty_state = RepositoryRulesetHistory.new(state: nil)
        serialized = RulesEngine::RulesetSerializer.history_to_html_string(empty_state)
        assert_nil serialized
      end

      test "shows bypass actors when a user has the appropriate permissions" do
        serialized = RulesEngine::RulesetSerializer.history_to_html_string(@ruleset.histories.first, user: @owner)
        assert_includes serialized, "bypass_actors"
      end

      test "serialize html tags to injection-safe encodings" do
        xss_ruleset = create(:repository_ruleset, :example_ruleset, source: @repo, name: '<script>alert("hello world")</script>')
        serialized = RulesEngine::RulesetSerializer.history_to_html_string(xss_ruleset.histories.first, user: @owner)

        assert_includes serialized, "&lt;script&gt"
        assert_includes serialized, "&lt;/script&gt;"
        refute_includes serialized, "<script>"
        refute_includes serialized, "</script>"
      end
    end
  end if GitHub.flipper[:rules_history].enabled?
end
