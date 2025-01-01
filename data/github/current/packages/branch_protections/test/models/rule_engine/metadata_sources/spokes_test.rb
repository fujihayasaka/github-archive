# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class RuleEnginePushesMetadataSourcesSpokesTest < GitHub::TestCase
  include PushTestHelper
  include RulesEngine::RefUpdateTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @repo = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd

    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @metadata_source = RuleEngine::MetadataSources::Spokes.new

    example_repo :repository_test_simple, @repo
  end

  test "fetches only new pushed commits for new branches" do
    pushes = create_pushes(1, "spokes-metadata-source-test")
    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: GitHub::NULL_OID, after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.oid
    refute result.next_cursor
  end

  test "fetches commits for existing branches" do
    pushes = create_pushes(1, @repo.default_branch)

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal 1, result.items.size
    assert_equal pushes.first[:current_ref_oid], result.items.first.oid
    assert result.items.first.message.starts_with? "Change"
    refute result.next_cursor
  end

  test "fetches commits across multiple pages" do
    pushes = create_pushes(1001, @repo.default_branch)

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.last[:current_ref_oid])

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal 1000, result.items.size
    assert_equal pushes.last[:current_ref_oid], result.items.first.oid
    assert result.next_cursor

    result = @metadata_source.commits(@repo, nil, ref_update, result.next_cursor)

    assert_equal 1, result.items.size
    assert_equal pushes.first[:current_ref_oid], result.items.first.oid
    refute result.next_cursor
  end

  test "fetches no commits for deleted branches" do
    pushes = create_pushes(1, "spokes-metadata-source-test")

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: GitHub::NULL_OID)

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 0
    refute result.next_cursor
  end

  test "fetches only new pushed blobs for new branches" do
    pushes = create_pushes(1, "spokes-metadata-source-test")
    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: GitHub::NULL_OID, after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.commit_oid
    assert_equal "blob1", result.items.first.path
    assert_equal 7, result.items.first.size
    refute result.next_cursor
  end

  test "fetches blobs for existing branches" do
    pushes = create_pushes(1, @repo.default_branch)

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.commit_oid
    assert_equal "blob1", result.items.first.path
    assert_equal 7, result.items.first.size
    refute result.next_cursor
  end

  test "fetches no blobs for deleted branches" do
    pushes = create_pushes(1, "spokes-metadata-source-test")

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: GitHub::NULL_OID)

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 0
    refute result.next_cursor
  end

  test "fetches blobs across multiple pages" do
    pushes = [
      create_blobs(1005, @repo.default_branch),
      create_blobs(10, @repo.default_branch, seed: 1006),
      create_blobs(3, @repo.default_branch, seed: 1016)
    ]

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.last[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)
    blobs = result.items
    next_cursor = result.next_cursor

    passes = 0
    while next_cursor do
      break if passes >= 10

      result = @metadata_source.blobs(@repo, nil, ref_update, next_cursor)
      blobs.append(result.items)
      next_cursor = result.next_cursor
    end

    refute next_cursor
    assert_equal 1018, blobs.size
  end

  test "skips fetching size for deleted blobs" do
    pushes = create_pushes(1, @repo.default_branch)

    branch = @repo.heads.find(@repo.default_branch)
    branch.append_commit({ message: "Delete file", committer: @repo.owner }, @repo.owner) do |files|
      files.remove("blob1")
    end

    pushes.append({
      ref_name: branch.name,
      previous_ref_oid: pushes.first[:current_ref_oid],
      current_ref_oid: branch.target_oid,
    })

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.last[:previous_ref_oid], after_oid: pushes.last[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.last[:current_ref_oid], result.items.first.commit_oid
    assert_equal "blob1", result.items.first.path
    assert_equal 0, result.items.first.size
    refute result.next_cursor
  end

  context "pre-receive phase" do
    test "fetches only new pushed commits for new branches" do
      pushes = create_test_pushes

      ref_update = create_ref_update(@repo, name: pushes.last[:ref_name],
                    before_oid: GitHub::NULL_OID, after_oid: pushes.last[:current_ref_oid])

      result = @metadata_source.commits(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal pushes.last[:current_ref_oid], result.items.first.oid
      assert_equal pushes.third[:current_ref_oid], result.items.last.oid
      refute result.next_cursor
    end

    test "fetches only new pushed commits for existing branches" do
      pushes = create_test_pushes

      ref_update = create_ref_update(@repo, name: pushes.last[:ref_name],
                    before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.last[:current_ref_oid])

      result = @metadata_source.commits(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal pushes.last[:current_ref_oid], result.items.first.oid
      assert_equal pushes.third[:current_ref_oid], result.items.last.oid
      refute result.next_cursor
    end

    test "fetches only new or changed blobs for new branches" do
      pushes = create_test_pushes

      ref_update = create_ref_update(@repo, name: pushes.last[:ref_name],
                    before_oid: GitHub::NULL_OID, after_oid: pushes.last[:current_ref_oid])

      result = @metadata_source.blobs(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal pushes.last[:current_ref_oid], result.items.first.commit_oid
      assert_equal "existing_path_2", result.items.first.path
      assert_equal "updated_content".length, result.items.first.size

      assert_equal pushes.third[:current_ref_oid], result.items.last.commit_oid
      assert_equal "new_path", result.items.last.path
      assert_equal "new_content".length, result.items.last.size
      refute result.next_cursor
    end

    test "fetches only new or changed blobs for existing branches" do
      pushes = create_test_pushes

      ref_update = create_ref_update(@repo, name: pushes.last[:ref_name],
                    before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.last[:current_ref_oid])

      result = @metadata_source.blobs(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal pushes.last[:current_ref_oid], result.items.first.commit_oid
      assert_equal "existing_path_2", result.items.first.path
      assert_equal "updated_content".length, result.items.first.size

      assert_equal pushes.third[:current_ref_oid], result.items.last.commit_oid
      assert_equal "new_path", result.items.last.path
      assert_equal "new_content".length, result.items.last.size
      refute result.next_cursor
    end

    test "moved files are included" do
      push = create_push(@repo.default_branch, "path", "content")

      new_branch = push_branch(repository: @repo, branch_name: "moved-files-test")
      new_branch.append_commit({ message: "Moved file", committer: @repo.owner }, @repo.owner) do |files|
        files.move("path", "some/other/path", "updated")
      end

      ref_update = create_ref_update(@repo, name: new_branch.qualified_name,
        before_oid: push[:current_ref_oid], after_oid: new_branch.target_oid)

      result = @metadata_source.blobs(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal "path", result.items.first.path

      refute_equal GitHub::NULL_OID, result.items.first.oid
      assert_equal "some/other/path", result.items.second.path
      assert_equal "updated".length, result.items.second.size
      refute_equal GitHub::NULL_OID, result.items.second.oid
    end

    test "renamed files are included" do
      push = create_push(@repo.default_branch, "path", "content")

      new_branch = push_branch(repository: @repo, branch_name: "moved-files-test")
      new_branch.append_commit({ message: "Renamed file", committer: @repo.owner }, @repo.owner) do |files|
        files.move("path", "renamed", "content")
      end

      ref_update = create_ref_update(@repo, name: new_branch.qualified_name,
        before_oid: push[:current_ref_oid], after_oid: new_branch.target_oid)

      result = @metadata_source.blobs(@repo, RuleEngine::Types::Phase::PreReceive, ref_update, nil)

      assert_equal 2, result.items.size
      assert_equal "path", result.items.first.path

      refute_equal GitHub::NULL_OID, result.items.first.oid
      assert_equal "renamed", result.items.second.path
      assert_equal "updated".length, result.items.second.size
      refute_equal GitHub::NULL_OID, result.items.second.oid
    end
  end

  test "allows fetching commits from non-ASCII references" do
    pushes = create_pushes(1, "ü")
    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: GitHub::NULL_OID, after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.oid
    refute result.next_cursor
  end

  test "allows fetching commits from non-UTF8 references" do
    pushes = create_pushes(1, "\xfe\xff")
    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: GitHub::NULL_OID, after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.commits(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.oid
    refute result.next_cursor
  end

  test "allows fetching blobs from non-ASCII references" do
    pushes = create_pushes(1, "ü")

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.commit_oid
    assert_equal "blob1", result.items.first.path
    assert_equal 7, result.items.first.size
    refute result.next_cursor
  end

  test "allows fetching blobs from non-UTF8 references" do
    pushes = create_pushes(1, "\xfe\xff")

    ref_update = create_ref_update(@repo, name: pushes.first[:ref_name],
                  before_oid: pushes.first[:previous_ref_oid], after_oid: pushes.first[:current_ref_oid])

    result = @metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal result.items.size, 1
    assert_equal pushes.first[:current_ref_oid], result.items.first.commit_oid
    assert_equal "blob1", result.items.first.path
    assert_equal 7, result.items.first.size
    refute result.next_cursor
  end

  def create_test_pushes
    initial_pushes = [
      create_push(@repo.default_branch, "existing_path_1", "existing_content"),
      create_push(@repo.default_branch, "existing_path_2", "existing_content")
    ]

    new_pushes = [
      create_push("spokes-metadata-source-test", "new_path", "new_content", create_branch: true),
      create_push("spokes-metadata-source-test", "existing_path_2", "updated_content")
    ]

    initial_pushes + new_pushes
  end

  def create_pushes(amount, branch_name)
    create_branch = branch_name != @repo.default_branch

    amount.times.map do |i|
      create_push(branch_name, "blob#{i + 1}", "change#{i + 1}", create_branch:)
    end
  end

  def create_blobs(amount, branch_name, seed: 0)
    create_branch = branch_name != @repo.default_branch

    push = push_changes(repository: @repo, branch_name: branch_name, create_branch:, changes: amount.times.map do |i|
      { path: "blob#{seed + i + 1}", content: "change#{seed + i + 1}" }
    end)

    {
      ref_name: push.ref,
      previous_ref_oid: push.before,
      current_ref_oid: push.after,
    }
  end

  def create_push(branch_name, blob_path, blob_content, create_branch: false)
    push = push_changes(repository: @repo, branch_name: branch_name, create_branch:, changes: [
      { path: blob_path, content: blob_content }
    ])

    {
      ref_name: push.ref,
      previous_ref_oid: push.before,
      current_ref_oid: push.after,
    }
  end
end
