# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryHasDockerfileTest < GitHub::TestCase
  fixtures do
    @repo = create :repository
  end

  test "empty repo" do
    example_repo :empty, @repo
    refute_predicate @repo, :has_dockerfile?
  end

  test "no dockerfile" do
    example_repo :simple, @repo
    refute_predicate @repo, :has_dockerfile?
  end

  test "with dockerfile" do
    example_repo :simple, @repo
    ref = @repo.heads.find("master")
    metadata = { committer: @repo.owner, message: "." }
    ref.append_commit(metadata, @repo.owner) do |files|
      files.add("Dockerfile", "(anything)\n")
    end

    assert_predicate @repo, :has_dockerfile?
  end
end
