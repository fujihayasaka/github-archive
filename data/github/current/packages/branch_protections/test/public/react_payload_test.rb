# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::ReactPayloadTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  class MockRefLoader < Git::Ref::Loader
    def initialize(repository, prefix, data)
      super(repository)

      refs = data.map do |ref, sha|
        ["refs/#{prefix}/#{ref}", sha]
      end

      build_and_cache_ref_data(refs)
    end
  end

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_org, admin: @org_admin)
    @repo = create(:repository, owner: @org)
  end

  setup do
    GitHub.flipper[:ruleset_skip_condition_count].disable
  end

  context "ruleset JSON payload" do
    test "returns inherited rulesets targeting a repository" do
      ruleset = create(:repository_ruleset, source: @org)
      create(:repository_rule_condition, :targets_repo, repo_name: "*", repository_ruleset: ruleset)

      inherited_ruleset = RulesEngine::ReactPayload.ruleset_json(ruleset, viewing_source: @repo)
      refute_nil inherited_ruleset
      assert_equal ruleset.id, inherited_ruleset[:id]
    end
  end
end
