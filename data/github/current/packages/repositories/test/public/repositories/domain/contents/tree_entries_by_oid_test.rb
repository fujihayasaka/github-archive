# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::TreeEntriesByOidTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :repository_contents_test)
    @repo_with_symlinks = create(:repository, from_example: :readmes)
  end

  setup do
    enable_cache_storage
    reset_cache
    Spokesd.enable_spokesd
  end

  teardown do
    disable_cache_storage
  end

  test "returns tree entries by oid" do
    entries = if TestEnv.test_all_features?
      T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: @repo, metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo)))
    else
      T.must(Repositories.domain.contents.tree_entries_by_oid(repository: @repo, tree_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414", root_tree_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414"))
    end

    expected_entries = [
      Repositories::Contents::TreeEntry.new(type: :tree, oid: "29a422c19251aeaeb907175e9b3219a9bed6c616", path: "dir", size: 0, mode: 0o40000, name: "dir"),
      Repositories::Contents::TreeEntry.new(type: :blob, oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4", path: "file", size: 5, mode: 0o100644, name: "file"),
      Repositories::Contents::TreeEntry.new(type: :submodule, oid: "4329a7b64767bcf0de9b88ced54f73073d446b66", path: "submodule", size: 0, mode: 0o160000, name: "submodule", submodule_path: TestEnv.test_all_features? ? "submodule" : nil,),
      Repositories::Contents::TreeEntry.new(type: :blob, oid: "345e6aef713208c8d50cdea23b85e6ad831f0449", path: "\xC2\xA0".b, size: 5, mode: 0o100644, name: "\xC2\xA0".b),
    ]

    assert_equal 4, entries.size
    assert_equal expected_entries, entries
  end

  test "returns tree entries at non-root tree" do
    entries = if TestEnv.test_all_features?
      T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: @repo, metadata: Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo, path: "dir"), path: "dir"))
    else
      T.must(Repositories.domain.contents.tree_entries_by_oid(repository: @repo, tree_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616", root_tree_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414"))
    end

    expected_entries = [
      Repositories::Contents::TreeEntry.new(type: :blob, oid: "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", path: ".keep", size: 0, mode: 0o100644, name: ".keep"),
    ]

    assert_equal 1, entries.size
    assert_equal expected_entries, entries
  end

  test "returns empty array for non-existent oid" do
    assert_nil Repositories.domain.contents.tree_entries_by_oid(repository: @repo, tree_oid: SecureRandom.hex(20), root_tree_oid: nil)
  end

  test "resolves symlinks" do
    metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo_with_symlinks)
    entries = if TestEnv.test_all_features?
      T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: @repo_with_symlinks, metadata: metadata))
    else
      T.must(Repositories.domain.contents.tree_entries_by_oid(repository: @repo_with_symlinks, tree_oid: "bf7dc03a73752e5fd8a5b263f19482d64b926ef3", root_tree_oid: "bf7dc03a73752e5fd8a5b263f19482d64b926ef3"))
    end

    expected_entries = [
      Repositories::Contents::TreeEntry.new(
        type: :blob,
        oid: "b03d3883bc777eb97627e899076a7727c8df8239",
        path: "README.md",
        size: 16,
        mode: 0o120000,
        name: "README.md",
        symlink_target: Repositories::Contents::TreeEntry.new(
          type: :blob,
          oid: "6729893bf551c96a8707558c9bdadefe527f0b95",
          path: "README.md",
          size: 9,
          mode: 0o100644,
          name: "README.md"
        )
      ),
      Repositories::Contents::TreeEntry.new(
        type: :tree,
        oid: "bad8516428cf461b4d279eb4ed1be5a27f8ec73c",
        path: "actual",
        size: 0,
        mode: 0o40000,
        name: "actual"
      ),
      Repositories::Contents::TreeEntry.new(
        type: :tree,
        oid: "c32e91552ff86e5642814316be15b64af179cf4f",
        path: "dir",
        size: 0,
        mode: 0o40000,
        name: "dir"
      ),
      Repositories::Contents::TreeEntry.new(
        type: :tree,
        oid: "e93514154f0717e4502de83d9f7527ad3b83a8cc",
        path: "midi",
        size: 0,
        mode: 0o40000,
        name: "midi"
      ),
      Repositories::Contents::TreeEntry.new(
        type: :tree,
        oid: "ca38fde4b9ebe4001389c96176e253469e2bb0d5",
        path: "readme",
        size: 0,
        mode: 0o40000,
        name: "readme"
      ),
      Repositories::Contents::TreeEntry.new(
        type: :tree,
        oid: "d4fc56d4882a8d7c344e47737ea373fa1f019355",
        path: "sym",
        size: 0,
        mode: 0o40000,
        name: "sym"
      )
    ]

    assert_equal 6, entries.size
    assert_equal expected_entries, entries
  end

  test "return cached tree entries" do
    repository = create(:repository, from_example: :readmes)

    GitHub.dogstats.reset
    original_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository)
    original_entries = T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: repository, metadata: original_metadata))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:tree_entries_by_metadata", "result:miss"])

    GitHub.dogstats.reset
    metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository)
    entries = T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: repository, metadata: metadata))
    assert_equal(original_metadata, metadata)
    assert_equal(original_entries, entries)
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:hit"])
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:tree_entries_by_metadata", "result:hit"])
  end

  test "return fresh entries if cache is busted" do
    repository = create(:repository, from_example: :repository_contents_test)

    GitHub.dogstats.reset
    original_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom")
    original_entries = T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: repository, metadata: original_metadata))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:tree_entries_by_metadata", "result:miss"])

    # commit to default branch to bust the metadata cache, but not the tree entries cache
    commit = perform_commit_to(repository, "main")

    GitHub.dogstats.reset
    metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom")
    entries = T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: repository, metadata: metadata))
    original_content_hash = original_metadata.to_h.merge(head_oid: commit.oid)
    original_metadata = Repositories::Contents::Metadata.new(**original_content_hash)
    assert_equal(original_metadata, metadata)
    assert_equal(original_entries, entries)
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:tree_entries_by_metadata", "result:hit"])

    # commit to custom branch to bust both the metadata and tree entries cache
    commit = perform_commit_to(repository, "custom")

    GitHub.dogstats.reset
    metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom")
    entries = T.must(Repositories.domain.contents.tree_entries_by_metadata(repository: repository, metadata: metadata))
    original_content_hash = original_metadata.to_h.merge(ref_commit_oid: commit.oid)
    assert_equal(Repositories::Contents::Metadata.new(**original_content_hash), metadata)
    assert_equal(original_entries, entries)
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:tree_entries_by_metadata", "result:miss"])
  end

  def perform_commit_to(repository, ref)
    repository.heads.find(ref).append_commit({
      message: "change stuff",
      committer: repository.owner,
      author: repository.owner,
    }, repository.owner)
  end
end
