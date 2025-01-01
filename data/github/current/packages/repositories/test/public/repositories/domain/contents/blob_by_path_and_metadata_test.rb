# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::BlobByPathAndMetadataTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :repository_test_simple)
    @repo_with_binary_file = create(:repository, from_example: :base64_file_contents)
    @symlink_repo = create(:repository, from_example: :readmes)
  end

  setup do
    enable_cache_storage
    reset_cache
    Spokesd.enable_spokesd
  end

  teardown do
    disable_cache_storage
  end

  test "returns a blob for a given path and metadata" do
    blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: @repo, path: "a",
      metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo, path: "a")
    ))

    assert_equal 4, blob.size
    assert_nil blob.symlink_target
    assert_equal 0o100644, blob.mode
    assert_equal "a\nb\n", blob.contents
    assert_equal "a", blob.name
    assert_equal "a", blob.path
    assert_equal "UTF-8", blob.encoding
    refute blob.truncated?
  end

  test "returns a blob with binary contents" do
    metadata =
    blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: @repo_with_binary_file, path: "b",
      metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo_with_binary_file, path: "b")
    ))

    assert_equal 725.kilobytes, blob.size
    assert_nil blob.symlink_target
    assert_equal 0o100644, blob.mode
    assert blob.binary?
    refute blob.truncated?
  end

  test "returns blob with resolved symlink"  do
    blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: @symlink_repo, path: "sym/README",
      metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @symlink_repo, path: "sym/README")
    ))

    assert_equal 19, blob.size
    assert_equal 0o120000, blob.mode
    assert_equal "", blob.contents # no contents are populated if the symlink was resolved, the data is in the symlink_target

    symlink_target = T.must(blob.symlink_target)
    assert_equal 9, symlink_target.size
    assert_equal 0o100644, symlink_target.mode
    assert_equal "# actual\n", symlink_target.contents
    assert_equal "README", symlink_target.name
  end

  test "returns blob with unresolved symlink if it cannot be resolved"  do
    blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: @symlink_repo, path: "sym/README.md",
      metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @symlink_repo, path: "sym/README.md")
    ))

    assert_equal 16, blob.size
    assert_equal 0o120000, blob.mode
    assert_equal "actual/actual.md", blob.contents # this path doesn't exist - that's why this symlink is unresolveable
    assert_nil blob.symlink_target
  end

  test "returns nil for nonexistent blob" do
    assert_nil Repositories.domain.contents.blob_by_path_and_metadata(repository: @repo, path: "foo", metadata: Repositories::Contents::Metadata.new)
  end

  context "large blobs" do
    test "omits blob content larger than 1mb"  do
      blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
        repository: @repo_with_binary_file, path: "b",
        metadata: Repositories::Contents::Metadata.new(
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_oid: "cfd2b9eca20b6fc0456dd1ab30ec2ce0416aca33",
          ref_commit_oid: "89f0a815d3c3ad390d819e889620d1cdbf2b9aa5",
          path_object_size: 2.megabytes,
        )
      ))

      SpokesAPI::Client.any_instance.expects(:get_blob_contents_streaming).never
      SpokesAPI::Client.any_instance.expects(:get_blob_contents).never

      assert_equal 2.megabytes, blob.size # uses the full size from the metadata
      assert_equal 0o100644, blob.mode
      assert blob.truncated?
      assert_equal 0, blob.contents.size # loads the contents up to 1mb total
    end

    test "loads full content up to max size if requested" do
      SpokesAPI::Client.any_instance.stubs(:get_blob_contents_streaming).returns("large content")

      blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
        repository: @repo_with_binary_file, path: "b",
        metadata: Repositories::Contents::Metadata.new(
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_oid: "cfd2b9eca20b6fc0456dd1ab30ec2ce0416aca33",
          ref_commit_oid: "89f0a815d3c3ad390d819e889620d1cdbf2b9aa5",
          path_object_size: 2.megabytes,
        ),
        load_full_content: true
      ))

      assert_equal 2.megabytes, blob.size # uses the full size from the metadata
      assert_equal 0o100644, blob.mode
      assert_equal "large content", blob.contents
    end

    test "doesn't attempt to load content if the blob is too large" do
      blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
        repository: @repo_with_binary_file, path: "b",
        metadata: Repositories::Contents::Metadata.new(
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_oid: "cfd2b9eca20b6fc0456dd1ab30ec2ce0416aca33",
          ref_commit_oid: "89f0a815d3c3ad390d819e889620d1cdbf2b9aa5",
          path_object_size: 101.megabytes,
        )
      ))

      SpokesAPI::Client.any_instance.expects(:get_blob_contents_streaming).never
      SpokesAPI::Client.any_instance.expects(:get_blob_contents).never

      assert_equal 101.megabytes, blob.size # uses the full size from the metadata
      assert blob.truncated?
      assert_equal 0, blob.contents.size # loads the contents up to 1mb total
    end
  end

  test "loads a blob with non ascii characters" do
    blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: @repo_with_binary_file, path: "c",
      metadata: Repositories::Contents::Metadata.new(
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_oid: "ab9d956d25a83e247f0fd0d08ad199fa415da3c3",
        ref_commit_oid: "f9b414ce1e40ebff4f3d46568035b77620d535a3",
        path_object_size: 19,
      )
    ))

    assert_equal 19, blob.size
    assert_equal 0o100644, blob.mode
    assert_equal "The \xE2\x80\x9Ctest\xE2\x80\x9D the\n".b, blob.contents
    assert_equal GitHub::Encoding::UTF8, blob.encoding
  end

  test "returns cached result" do
    enable_feature_flag(:blob_contents_with_cache)

    repository = create(:repository, from_example: :readmes)

    metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, path: "sym/README")

    GitHub.dogstats.reset
    original_blob = T.must(Repositories.domain.contents.blob_by_path_and_metadata(
      repository: repository,
      path: "sym/README",
      metadata:
    ))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:blob_by_path_and_metadata", "result:miss"])

    GitHub.dogstats.reset
    assert_equal(original_blob, Repositories.domain.contents.blob_by_path_and_metadata(
      repository: repository,
      path: "sym/README",
      metadata:
    ))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:blob_by_path_and_metadata", "result:hit"])

    perform_commit_to(repository, "master")

    GitHub.dogstats.reset
    assert_equal(original_blob, Repositories.domain.contents.blob_by_path_and_metadata(
      repository: repository,
      path: "sym/README",
      metadata:
    ))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:blob_by_path_and_metadata", "result:hit"])
  end

  def perform_commit_to(repository, ref)
    repository.heads.find(ref).append_commit({
      message: "change stuff",
      committer: repository.owner,
      author: repository.owner,
    }, repository.owner)
  end
end
