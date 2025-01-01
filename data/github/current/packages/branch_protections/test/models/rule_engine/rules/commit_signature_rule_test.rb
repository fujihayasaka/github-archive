# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesCommitSignatureRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper
  include GpgKeyHelper

  fixtures do
    signing_key = create_gpg_key
    @user = signing_key.user
    @repo = create(:repository, owner: @user)

    ca = FakeCA.new("/CN=root1")
    @cert = ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(ca.parsed)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @rule = T::let(RuleEngine::Rules::CommitSignatureRule.new, RuleEngine::Rules::CommitSignatureRule)

    example_repo :simple, @repo
  end

  test "only supports commit metadata" do
    assert_equal @rule.supported_metadata_types, [:commit]
  end

  test "fails when not all commits have verified signatures" do
    rule_config = build(:repository_rule_configuration, rule_type: "ruleset_required_signatures")

    signed_commit = create_signed_commit

    unsigned_commits = 2.times.map do |i|
      @repo.heads[@repo.default_branch].append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
        files.add "test#{i}", "Test"
      end
    end

    candidates = [
      create_commit_candidate(id: signed_commit.oid, gpg_signature: signed_commit.signature),
      create_commit_candidate(id: unsigned_commits[0].oid, gpg_signature: "invalid"),
      create_commit_candidate(id: unsigned_commits[1].oid),
    ]

    @ref_update = create_branch_update(@repo, after_oid: T.must(candidates.last.oid))

    result = @rule.bulk_evaluate_candidates(@context, @ref_update, [rule_config], candidates)

    assert_equal 3, result[rule_config]&.size
    assert_equal 2, result[rule_config]&.count { |r| !r.success? }
    assert_equal 1, result[rule_config]&.count { |r| r.success? }
  end

  test "succeeds when all commits have verified signatures" do
    # also verify that commits are not added to the AuthenticCommit table
    assert_equal 0, AuthenticCommit.count

    rule_config = build(:repository_rule_configuration, rule_type: "ruleset_required_signatures")

    signed_commits = 2.times.map { |_| create_signed_commit }
    candidates = signed_commits.map { |commit| create_commit_candidate(id: commit.oid, gpg_signature: commit.signature) }

    @ref_update = create_branch_update(@repo, after_oid: T.must(T.must(candidates.last).oid))

    result = @rule.bulk_evaluate_candidates(@context, @ref_update, [rule_config], candidates)

    assert_equal 2, result[rule_config]&.size
    assert result[rule_config]&.all? { |r| r.success? }

    assert_equal 0, AuthenticCommit.count
  end

  private

  sig { returns(Commit) }
  def create_signed_commit
    oid = @cert.create_signed_commit(@repo, @user, refname: @repo.default_branch)
    T.must(Repositories.domain.commits.by_oid(repository: @repo, commit_oid: oid))
  end
end
