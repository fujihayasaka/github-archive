# typed: strict
# frozen_string_literal: true

module RulesEngine
  module BypassTestHelper
    extend T::Helpers

    requires_ancestor { GitHub::TestCase }

    # takes in a block that should make the bypass allowed
    sig do
      params(
        repo: Repository,
        branch: String,
        metadata: { message: T.nilable(String), author_email: T.nilable(String), committer_email: T.nilable(String), blobs: T::Hash[String, T.nilable(String)] },
        user: User,
        write_operation: T::Boolean,
        blk: T.proc.params(x: RuleEngine::RuleSuite).void
      ).void
    end
    def validate_bypass_allowed_push(repo, branch, metadata, user, write_operation: false, &blk)
      rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(repo, repo.heads[branch].target_oid, user, metadata, target_ref_name: branch)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

      yield(rule_suite)

      rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(repo, repo.heads[branch].target_oid, user, metadata, target_ref_name: branch)
      refute rule_suite.rules_fulfilled?, "Expected rules to still be failing"
      assert rule_suite.action_permitted?, "Expected bypass to be allowed after bypass is added"
    end

    # takes in a block that should not make the bypass allowed
    sig do
      params(
        repo: Repository,
        branch: String,
        metadata: { message: T.nilable(String), author_email: T.nilable(String), committer_email: T.nilable(String), blobs: T::Hash[String, T.nilable(String)] },
        user: RuleEngine::Types::Actor,
        write_operation: T::Boolean,
        blk: T.proc.params(x: RuleEngine::RuleSuite).void
      ).void
    end
    def validate_bypass_denied_push(repo, branch, metadata, user, write_operation: false, &blk)
      rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(repo, repo.heads[branch].target_oid, user, metadata, target_ref_name: branch)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

      yield(rule_suite)

      rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(repo, repo.heads[branch].target_oid, user, metadata, target_ref_name: branch)
      refute rule_suite.rules_fulfilled?, "Expected rules to still be failing"
      refute rule_suite.action_permitted?, "Expected bypass to still be denied after bypass is added"
    end

    # takes in a block that should make the bypass allowed
    sig do
      params(
        repo: Repository,
        ref_update: Git::Ref::Update,
        user: RuleEngine::Types::Actor,
        blk: T.proc.params(x: RuleEngine::RuleSuite).void
      ).void
    end
    def validate_bypass_allowed(repo, ref_update, user, &blk)
      rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(repo, [ref_update], user).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

      yield(rule_suite)

      rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(repo, [ref_update], user).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to still be failing"
      assert rule_suite.action_permitted?, "Expected bypass to be allowed after bypass is added"
    end

    # takes in a block that should not make the bypass allowed
    sig do
      params(
        repo: Repository,
        ref_update: Git::Ref::Update,
        user: RuleEngine::Types::Actor,
        blk: T.proc.params(x: RuleEngine::RuleSuite).void
      ).void
    end
    def validate_bypass_denied(repo, ref_update, user, &blk)
      rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(repo, [ref_update], user).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

      yield(rule_suite)

      rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(repo, [ref_update], user).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to still be failing"
      refute rule_suite.action_permitted?, "Expected bypass to still be denied after bypass is added"
    end
  end
end
