# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::MultiRepositoryPolicyCacheTest < GitHub::TestCase
  test "returns the correct fulfilled policy" do
    monalisa = create(:paid_user, name: "monalisa")
    repo = create(:repository, name: "test-repo", owner: monalisa, from_example: :pull_request_source)
    second_repo = create(:repository, name: "test-repo2", owner: monalisa)
    codespace = create(:codespace, repository: repo, owner: monalisa)
    second_codespace = create(:codespace, repository: second_repo, owner: monalisa)
    pull_request = create(:pull_request, repository: repo, base_repository: repo, head_repository: repo, head_ref: "master-merged-topic")
    third_codespace = create(:codespace, repository: repo, owner: monalisa, pull_request:)

    policy_cache = Codespaces::MultiRepositoryPolicyCache.new([codespace, second_codespace, third_codespace])

    # The return value should not be a promise
    assert_kind_of Codespaces::RepositoryPolicy, policy_cache.get(codespace)
    assert_equal repo, policy_cache.get(codespace).repository
    refute policy_cache.get(codespace).pull_request

    assert_equal second_repo, policy_cache.get(second_codespace).repository
    refute policy_cache.get(second_codespace).pull_request

    assert_equal repo, policy_cache.get(third_codespace).repository
    assert_equal pull_request, policy_cache.get(third_codespace).pull_request
  end
end
