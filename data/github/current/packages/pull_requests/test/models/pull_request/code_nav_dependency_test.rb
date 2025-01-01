# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestCodeNavDependencyTest < GitHub::TestCase

  def create_pull_with(&blk)
    user = create(:user)
    repo = create(:repository, owner: user, from_example: :pull_request_source)


    base_ref = repo.heads.find("master")
    head_ref = repo.heads.create("topic", base_ref.target, repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: repo.owner,
    }, repo.owner) do |files|
      blk[files]
    end

    create(:pull_request,
      repository: repo,
      base_repository: repo,
      base_user: repo.owner,
      base_ref: "master",
      head_repository: repo,
      head_user: repo.owner,
      head_ref: "topic",
      user: repo.owner,
    )
  end

  context "all_languages_in_diff" do
    test "works in the trivial case" do
      pull = create_pull_with do |files|
        files.add("bowie.rb", "p 'hello'\n")
      end

      assert_equal pull.all_languages_in_diff, ["Ruby"]
    end

    test "returns empty array when no languages are recognized" do
      pull = create_pull_with do |files|
        files.add("lacey.unrecognizedfile", "foo")
      end

      assert_empty pull.all_languages_in_diff
    end

    test "returns multiple languages appropriately" do
      pull = create_pull_with do |files|
        files.add("bowie.rb", "p 'hello'\n")
        files.add("lacey.py", "print('goodbye')\n")
      end

      assert_equal pull.all_languages_in_diff.sort, %w[Python Ruby]
    end
  end
end
