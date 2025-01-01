# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class RuleEnginePushesMetadataSourcesLocalTest < GitHub::TestCase
  include PushTestHelper
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd

    @context = RuleEngine::RuleEvaluationContext.new(@repo)

    example_repo :repository_test_simple, @repo
  end

  test "fetches blobs recursively from Spokes for directories" do
    push = push_changes(repository: @repo, branch_name: @repo.default_branch, changes: [
      { path: "dir/blob-1", content: "blob-1" },
      { path: "dir/sub-dir/blob-2", content: "blob-2" }
    ])

    ref_update = create_ref_update(@repo, name: push.ref, before_oid: push.after, after_oid: GitHub::PENDING_OID)

    metadata_source = RuleEngine::MetadataSources::Local.new(blobs: [
      RuleEngine::MetadataSources::Types::BlobCandidate.new(
        oid: nil,
        commit_oid: nil,
        path: "dir/",
        size: 0,
        contents: nil,
      )
    ])

    result = metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal 2, result.items.size
    refute result.next_cursor

    blob1 = T.must(result.items.first)
    assert_equal "dir/blob-1", blob1.path
    assert_equal 6, blob1.size

    blob2 = T.must(result.items.second)
    assert_equal "dir/sub-dir/blob-2", blob2.path
    assert_equal 6, blob2.size
  end

  test "fetches blobs recursively from Spokes for directories across multiple pages" do
    # NOTE: Although we only expect for a page to include 1000 results, the Spokes endpoint will return up to 10000 per request.

    push = push_changes(repository: @repo, branch_name: @repo.default_branch, changes: [
      { path: "dir/sub-dir-1/blob-1", content: "blob-1" },
      { path: "dir/sub-dir-2/blob-2", content: "blob-2" }
    ].concat(10010.times.map { |i| { path: "dir/sub-dir-3/blob-#{"#{i + 3}".rjust(5, "0")}", content: "blob-#{i + 3}" } }))

    ref_update = create_ref_update(@repo, name: push.ref, before_oid: push.after, after_oid: GitHub::PENDING_OID)

    metadata_source = RuleEngine::MetadataSources::Local.new(blobs: [
      RuleEngine::MetadataSources::Types::BlobCandidate.new(
        oid: nil,
        commit_oid: nil,
        path: "README.md",
        size: 0,
        contents: nil,
      ),
      RuleEngine::MetadataSources::Types::BlobCandidate.new(
        oid: nil,
        commit_oid: nil,
        path: "dir/sub-dir-3/",
        size: 0,
        contents: nil,
      ),
      RuleEngine::MetadataSources::Types::BlobCandidate.new(
        oid: nil,
        commit_oid: nil,
        path: "dir/sub-dir-1/",
        size: 0,
        contents: nil,
      )
    ])

    result = metadata_source.blobs(@repo, nil, ref_update, nil)

    assert_equal 10001, result.items.size
    assert result.next_cursor

    blob1 = T.must(result.items.first)
    assert_equal "README.md", blob1.path
    assert_equal 0, blob1.size

    blob2 = T.must(result.items.second)
    assert_equal "dir/sub-dir-3/blob-00003", blob2.path
    assert_equal 6, blob2.size

    last_blob = T.must(result.items.last)
    assert_equal "dir/sub-dir-3/blob-10002", last_blob.path
    assert_equal 10, last_blob.size

    result = metadata_source.blobs(@repo, nil, ref_update, result.next_cursor)

    assert_equal 11, result.items.size
    refute result.next_cursor

    blob1 = T.must(result.items.first)
    assert_equal "dir/sub-dir-3/blob-10003", blob1.path
    assert_equal 10, blob1.size

    second_to_last_blob = T.must(result.items.second_to_last)
    assert_equal "dir/sub-dir-3/blob-10012", second_to_last_blob.path
    assert_equal 10, second_to_last_blob.size

    last_blob = T.must(result.items.last)
    assert_equal "dir/sub-dir-1/blob-1", last_blob.path
    assert_equal 6, last_blob.size
  end
end
