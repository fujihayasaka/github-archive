# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class SpokesAPIClientTest < GitHub::TestCase
  include PushTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @repo = create :repository, from_example: :repository_test_simple

    @master_oid = @repo.rev_parse("refs/heads/master")
    @annotated_oid = @repo.rev_parse("refs/tags/v1")
    @tag_oid = @repo.rev_parse("refs/tags/v2")
  end

  setup do
    Spokesd.enable_spokesd
    @client = SpokesAPI::Client.for_repository(@repo.id, network_id: @repo.network_id)
  end

  context "resolve_object" do
    test "raises for missing object_name" do
      assert_raises TypeError do
        @client.resolve_object(object_name: nil)
      end
    end

    test "returns nil on .." do
      @client.client.objects.expects(:resolve_object).never
      assert_nil @client.resolve_object(object_name: "..")
    end

    test "returns the oid when .. is in the path" do
      @client.client.objects.stubs(resolve_object: stub("response", error: nil, data: stub("ResolveObjectResponse", oid: stub("types.ObjectID", id: "success"))))
      assert_equal "success", @client.resolve_object(object_name: "main:dir/file..txt")
    end

    test "returns the oid on a valid oid" do
      oid = "bb7f9d7da836d8a0839ecf4b0dd7add0b7ebe131"

      assert_equal oid, @client.resolve_object(object_name: oid)
    end

    test "returns a resolved oid for a valid ref" do
      oid = @client.resolve_object(object_name: "refs/heads/master")
      assert_equal "63611721afd41f58f801d66e543d8288b4c5eb44", oid
    end

    test "returns nil for an unknown revision" do
      assert_nil @client.resolve_object(object_name: "refs/heads/not_found")
    end
  end

  test "returns all blobs for a repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")
    new_ref_update = push_change(@repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = @client.list_historical_reachable_blobs(reference_updates: ref_updates, cursor: nil)

    assert_equal 2, result.reachable_blobs.size
    assert_equal "blob2", result.reachable_blobs[0].path.name
    assert_equal "blob1", result.reachable_blobs[1].path.name
    refute result.next_cursor
  end

  test "returns newly reachable blobs for a fork repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")

    forker = create(:user)
    fork_repo = create(:fork_repository, forker: forker, fork_repo: @repo)
    fork_client = SpokesAPI::Client.for_repository(fork_repo.id, network_id: fork_repo.network_id)

    new_ref_update = push_change(fork_repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = fork_client.list_newly_reachable_blobs(reference_updates: ref_updates, cursor: nil, base_repository_id: @repo.id)

    assert_equal 1, result.reachable_blobs.size
    assert_equal "blob2", result.reachable_blobs[0].path.name
    refute result.next_cursor
  end

  test "returns commits for a repository based on a list of ids" do
    ref_update = push_change(@repo, "blob1")

    result = @client.list_commits_for_ids(oids: [ref_update[:current_ref_oid]], cursor: nil)

    assert_equal 1, result.commits.size
    assert_equal ref_update[:current_ref_oid], result.commits[0].oid.id
    refute result.next_cursor
  end

  test "returns commits for a repository based on a single revision" do
    ref_update = push_change(@repo, "blob1")
    ref_update2 = push_change(@repo, "blob2")
    ref_update3 = push_change(@repo, "blob3", "develop", create_branch: true)
    ref_update4 = push_change(@repo, "blob4", "develop")
    ref_update5 = push_change(@repo, "blob5")

    result = @client.list_commits_for_revisions(revisions: ["#{ref_update[:current_ref_oid]}..#{ref_update4[:current_ref_oid]}"], cursor: nil)

    assert_equal 3, result.commits.size
    assert_equal ref_update4[:current_ref_oid], result.commits[0].oid.id
    assert_equal ref_update3[:current_ref_oid], result.commits[1].oid.id
    assert_equal ref_update2[:current_ref_oid], result.commits[2].oid.id
    refute result.next_cursor

    result = @client.list_commits_for_revisions(revisions: ["#{ref_update[:current_ref_oid]}..#{ref_update5[:current_ref_oid]}"], cursor: nil)

    assert_equal 2, result.commits.size
    assert_equal ref_update5[:current_ref_oid], result.commits[0].oid.id
    assert_equal ref_update2[:current_ref_oid], result.commits[1].oid.id
    refute result.next_cursor
  end

  test "returns commits for a repository based on a list of revisions" do
    ref_updates = [
      push_change(@repo, "blob1"),
      push_change(@repo, "blob2"),
      push_change(@repo, "blob3", "develop", create_branch: true),
      push_change(@repo, "blob4", "develop"),
      push_change(@repo, "blob5")
    ]

    result = @client.list_commits_for_revisions(
      revisions: [
        "#{ref_updates[0][:current_ref_oid]}..#{ref_updates[3][:current_ref_oid]}",
        "#{ref_updates[0][:current_ref_oid]}..#{ref_updates[4][:current_ref_oid]}"
      ],
      cursor: nil
    )

    assert_equal 4, result.commits.size
    result_commit_oids = result.commits.map { |commit| commit.oid.id }
    ref_update_commit_oids = ref_updates.map { |ref_update| ref_update[:current_ref_oid] }
    assert (result_commit_oids - ref_update_commit_oids).empty?
    refute result.next_cursor
  end

  test "returns all reachable commits for a repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")
    new_ref_update = push_change(@repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = @client.list_historical_commits(reference_updates: ref_updates, cursor: nil)

    assert_equal 2, result.commits.size
    assert_equal new_ref_update[:current_ref_oid], result.commits[0].oid.id
    assert_equal default_ref_update[:current_ref_oid], result.commits[1].oid.id
    refute result.next_cursor
  end

  test "returns newly reachable commits for a fork repository based on a list of ref updates" do
    default_ref_update = push_change(@repo, "blob1")

    forker = create(:user)
    fork_repo = create(:fork_repository, forker: forker, fork_repo: @repo)
    fork_client = SpokesAPI::Client.for_repository(fork_repo.id, network_id: fork_repo.network_id)

    new_ref_update = push_change(fork_repo, "blob2", "develop", create_branch: true)

    ref_updates = [{
      ref_name: new_ref_update[:ref_name],
      previous_ref_oid: default_ref_update[:previous_ref_oid],
      current_ref_oid: new_ref_update[:current_ref_oid],
    }]

    result = fork_client.list_newly_reachable_commits(reference_updates: ref_updates, cursor: nil, base_repository_id: @repo.id)

    assert_equal 1, result.commits.size
    assert_equal ref_updates.first[:current_ref_oid], result.commits[0].oid.id
    refute result.next_cursor
  end

  test "gets default branch of the repository" do
    result = @client.get_default_branch
    assert_equal "refs/heads/master", result

    non_utf_branch = String.new("\xBE\xC8\xB3\xE7\xC7\xCF\xBC\xBC\xBF\xE4", encoding: Encoding.find("ASCII-8BIT")) # 안녕하세요 (annyeonghaseyo) = hello (in Korean)
    push_change(@repo, "blob2", non_utf_branch, create_branch: true)
    @repo.update_default_branch_spokes("refs/heads/#{non_utf_branch}")

    result = @client.get_default_branch
    assert_equal "refs/heads/#{non_utf_branch.dup.force_encoding("UTF-8")}", result
  end

  context "resolve_references" do
    test "with valid references" do
      result = @client.resolve_references(%w[refs/heads/master refs/tags/v1])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
    end

    test "with missing ref" do
      assert_equal [["refs/heads/foobar", nil]], @client.resolve_references(%w[refs/heads/foobar])
    end

    test "with duplicate slashes" do
      @repo.heads.create("branch/with/so/many/slashes", @tag_oid, @repo.owner)
      result = @client.resolve_references(%w[
        refs/heads/master
        refs//heads/master
        refs/heads//master
        refs/heads////master
        refs////heads////master
        refs/tags/v1
        refs/tags////v1
        refs////tags////v1
        refs/heads/branch/with/so/many/slashes
        refs//heads/branch/with/so/many/slashes
        refs/heads/branch//with/so/many/slashes
        refs///heads/branch///with/so/many///slashes
      ])

      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs//heads/master", @master_oid],
          ["refs/heads//master", @master_oid],
          ["refs/heads////master", @master_oid],
          ["refs////heads////master", @master_oid],
          ["refs/tags/v1", @annotated_oid],
          ["refs/tags////v1", @annotated_oid],
          ["refs////tags////v1", @annotated_oid],
          ["refs/heads/branch/with/so/many/slashes", @tag_oid],
          ["refs//heads/branch/with/so/many/slashes", @tag_oid],
          ["refs/heads/branch//with/so/many/slashes", @tag_oid],
          ["refs///heads/branch///with/so/many///slashes", @tag_oid],
        ],
        result,
        "failed to match libgit2's slash compression behavior"
      )
    end

    test "with partial success" do
      result = @client.resolve_references(%w[
        refs/heads/master
        refs/heads/foobar
        refs/tags/v1
      ])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/heads/foobar", nil],
          ["refs/tags/v1", @annotated_oid]
        ],
        result
      )
      assert_equal [["refs/heads/foobar", nil]], @client.resolve_references(%w[refs/heads/foobar])
    end

    test "can see hidden refs" do
      @repo.refs.create("refs/__gh__/hidden", @tag_oid, @repo.owner)
      assert_equal [["refs/__gh__/hidden", @tag_oid]], @client.resolve_references(%w[refs/__gh__/hidden])
    end

    test "can handle multibyte refs" do
      @repo.refs.create("refs/tags/１", @tag_oid, @repo.owner)
      result = @client.resolve_references(%w[refs/heads/master refs/tags/１])
      assert_equal(
        [
          ["refs/heads/master", @master_oid],
          ["refs/tags/１", @tag_oid]
        ],
        result
      )
    end

    test "never mutates args" do
      refs = %w[
        refs/heads/some-branch
        20211028_リリ
        refs/special/////foo
      ]
      backup = refs.map(&:dup) # deep_dup
      @client.resolve_references(refs)
      assert_equal(backup, refs, "`refs` was modified by the call to `resolve_references`!")
    end

    test "can handle inputs with newlines" do
      refs = [
        "refs/tags/v1",
        "refs/heads/master\nrefs/tags/v2"
      ]
      result = @client.resolve_references(refs)
      assert_equal(
        [
          ["refs/tags/v1", @annotated_oid],
          ["refs/heads/master\nrefs/tags/v2", nil]
        ],
        result
      )
    end
  end

  def push_change(repository, path, branch_name = repository.default_branch, create_branch: false)
    push = push_changes(repository: repository, branch_name: branch_name, create_branch: create_branch, changes: [
      { path: path, content: "" }
    ])

    {
      ref_name: push.ref,
      previous_ref_oid: push.before,
      current_ref_oid: push.after,
    }
  end
end
