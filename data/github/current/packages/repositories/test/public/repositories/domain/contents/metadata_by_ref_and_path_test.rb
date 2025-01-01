# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::MetadataByRefAndPathTest < GitHub::TestCase
  include DogstatsTestHelpers

  BASE_REPO_METADATA = {
    head_oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a"
  }.freeze

  DEFAULT_BRANCH_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a",
    ref_name: "main",
    root_tree_entry_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414"
  ).freeze

  TAG_V1_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "5a87dd0219beebaba7574d82cfa1f348a2a616de",
    ref_name: "v1",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  TAG_V2_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "8a2253252eec0aabc0ffde593c56a951ad70f8c9",
    ref_name: "v2",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  BRANCH_CUSTOM_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "46b5b1e7eabed5d93b4933315dcb395ec65e1f7a",
    ref_name: "custom",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  OID_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "61a4709fef5564d5910963dd516efc856fc5241e",
    ref_name: "61a4709fef5564d5910963dd516efc856fc5241e",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  CUSTOM_REF_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "46b5b1e7eabed5d93b4933315dcb395ec65e1f7a",
    ref_name: "refs/my-custom-ref",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  SHORT_OID_METADATA = OID_METADATA.merge(
    ref_name: "61a4709",
  ).freeze

  GH_REF_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
    ref_name: "refs/__gh__/hidden",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  BRANCH_AND_TAG_SAME_NAME_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
    ref_name: "branch_and_tag",
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  fixtures do
    @repo = create(:repository, from_example: :repository_contents_test)
    @repo_no_head = create(:repository, from_example: :repository_no_head)
    @repo_head_branch = create(:repository, from_example: :repository_head_branch)
    @empty_repo = create(:repository)
    @repo_with_strange_blob = create(:repository, from_example: :base64_file_contents)
  end

  setup do
    enable_cache_storage
    reset_cache
    Spokesd.enable_spokesd
  end

  teardown do
    disable_cache_storage
  end

  test "empty repository" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: @empty_repo)

    assert_equal(Repositories::Contents::Metadata::EMPTY_REPOSITORY, content_metadata)
    assert_predicate(content_metadata, :empty_repository?)
  end

  test "repository no head" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo_no_head)

    refute_equal(Repositories::Contents::Metadata::EMPTY_REPOSITORY, content_metadata)
    refute_predicate(content_metadata, :empty_repository?)
    assert_equal(Repositories::Contents::Metadata.new, content_metadata)
  end

  test "non-existent branch" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "non-existent"
    )

    assert_equal(Repositories::Contents::Metadata.new(**BASE_REPO_METADATA), content_metadata)
  end

  test "non-existent path" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      path: "non-existent"
    )

    assert_equal(Repositories::Contents::Metadata.new(**DEFAULT_BRANCH_METADATA), content_metadata)
  end

  test "missing path with line break" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      path: "missing/\npath"
    )

    assert_equal(Repositories::Contents::Metadata.new(**DEFAULT_BRANCH_METADATA), content_metadata)
  end

  test "by branch qualified ref name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/heads/custom",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_CUSTOM_METADATA.merge(
        ref_name: "refs/heads/custom",
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree,
        path_object_mode: 0o040000,
        path_object_size: 33,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "paths with leading slashes" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/heads/custom",
      path: "/file"
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_CUSTOM_METADATA.merge(
        ref_name: "refs/heads/custom",
        path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 5,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "ref with leading slashes" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "/custom",
      path: "/file"
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_CUSTOM_METADATA.merge(
        ref_name: "/custom",
        path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 5,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "refs/__gh__ internal ref" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/__gh__/hidden",
      path: "file"
    )

    expected = Repositories::Contents::Metadata.new(
      **GH_REF_METADATA.merge(
        path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 5,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "branch and tag with same name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "branch_and_tag",
      path: "file"
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_AND_TAG_SAME_NAME_METADATA.merge(
        path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 5,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "by tag full ref name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/tags/v1",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      **TAG_V1_METADATA.merge(
        ref_name: "refs/tags/v1",
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree,
        path_object_mode: 0o040000,
        path_object_size: 33,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "by HEAD pointer" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "HEAD",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      **DEFAULT_BRANCH_METADATA.merge(
        ref_name: "HEAD",
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree,
        path_object_mode: 0o040000,
        path_object_size: 33,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "by HEAD as a branch" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo_head_branch,
      ref: "HEAD",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      head_oid: "e8e6497b695cafa6a930a415cb656c78994b5b7e",
      ref_commit_oid: "1bcd7d10b0453c69d48f9e96f77e6798b59ec15f",
      root_tree_entry_oid: "218167701b299bbe3397208c38c8a73e0a7848f9",
      ref_name: "HEAD",
      path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
      path_object_type: :tree,
      path_object_mode: 0o040000,
      path_object_size: 33,
    )

    assert_equal(expected, content_metadata)
  end

  test "non-breaking space file name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      path: "\u00A0" # the same as \xC2\xA0
    )

    expected = Repositories::Contents::Metadata.new(
      **DEFAULT_BRANCH_METADATA.merge(
        path_object_oid: "345e6aef713208c8d50cdea23b85e6ad831f0449",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 5,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "ref with special characters" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "réference",
      path: "\u00A0"
    )

    expected = Repositories::Contents::Metadata.new(
      head_oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a",
      ref_commit_oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a",
      ref_name: "réference",
      root_tree_entry_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414",
      path_object_oid: "345e6aef713208c8d50cdea23b85e6ad831f0449",
      path_object_type: :blob,
      path_object_mode: 0o100644,
      path_object_size: 5,
    )

    assert_equal(expected, content_metadata)
  end

  test "ref + path with open bracket in the ref name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "foo{bar",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      **BASE_REPO_METADATA.merge(
        ref_commit_oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a",
        ref_name: "foo{bar",
        root_tree_entry_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414",
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree,
        path_object_mode: 0o040000,
        path_object_size: 0,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "ref name with -g in the ref name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/tags/v2-g5a87dd02"
    )

    expected = Repositories::Contents::Metadata.new(
      **BASE_REPO_METADATA.merge(
        ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
        ref_name: "refs/tags/v2-g5a87dd02",
        root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
        path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
        path_object_type: :tree
      )
    )

    assert_equal(expected, content_metadata)
  end

  context "by branch default" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: @repo)

      expected = Repositories::Contents::Metadata.new(
        **DEFAULT_BRANCH_METADATA.merge(
          path_object_oid: "42221520b35ffacb519bd010d9b61bf2b8faa414",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **DEFAULT_BRANCH_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **DEFAULT_BRANCH_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **DEFAULT_BRANCH_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by tag v1" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v1"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V1_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v1",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V1_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v1",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V1_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v1",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V1_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by tag v2 (annotated)" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v2"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V2_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v2",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V2_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v2",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V2_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "v2",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **TAG_V2_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by custom branch" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "custom"
      )

      expected = Repositories::Contents::Metadata.new(
        **BRANCH_CUSTOM_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "custom",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **BRANCH_CUSTOM_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "custom",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **BRANCH_CUSTOM_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "custom",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **BRANCH_CUSTOM_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by oid" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709fef5564d5910963dd516efc856fc5241e"
      )

      expected = Repositories::Contents::Metadata.new(
        **OID_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709fef5564d5910963dd516efc856fc5241e",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **OID_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709fef5564d5910963dd516efc856fc5241e",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **OID_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709fef5564d5910963dd516efc856fc5241e",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **OID_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by custom ref" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "refs/my-custom-ref"
      )

      expected = Repositories::Contents::Metadata.new(
        **CUSTOM_REF_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "refs/my-custom-ref",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **CUSTOM_REF_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "refs/my-custom-ref",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **CUSTOM_REF_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "refs/my-custom-ref",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **CUSTOM_REF_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  context "by short oid" do
    test "root dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709"
      )

      expected = Repositories::Contents::Metadata.new(
        **SHORT_OID_METADATA.merge(
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
          path_object_type: :tree
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "dir metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709",
        path: "dir"
      )

      expected = Repositories::Contents::Metadata.new(
        **SHORT_OID_METADATA.merge(
          path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
          path_object_type: :tree,
          path_object_mode: 0o040000,
          path_object_size: 33,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "file metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709",
        path: "file"
      )

      expected = Repositories::Contents::Metadata.new(
        **SHORT_OID_METADATA.merge(
          path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
          path_object_type: :blob,
          path_object_mode: 0o100644,
          path_object_size: 5,
        )
      )

      assert_equal(expected, content_metadata)
    end

    test "submodule metadata" do
      content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
        repository: @repo,
        ref: "61a4709",
        path: "submodule"
      )

      expected = Repositories::Contents::Metadata.new(
        **SHORT_OID_METADATA.merge(
          path_object_oid: "4329a7b64767bcf0de9b88ced54f73073d446b66",
          path_object_type: :submodule,
          path_object_size: 0,
          path_object_mode: 0o160000,
        )
      )

      assert_equal(expected, content_metadata)
    end
  end

  test "defaults to root tree at correct ref when path string is empty" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "branch_and_tag",
      path: ""
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_AND_TAG_SAME_NAME_METADATA.merge(
        path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
        path_object_type: :tree,
      )
    )

    assert_equal(expected, content_metadata)
  end

  test "finds blob with git describe revision syntax in name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo_with_strange_blob,
      path: "dir/foo-g275a2e41",
    )

    expected = Repositories::Contents::Metadata.new(
        head_oid: "e62177f1865f707cc9bcc7428c1c029fffa13bf3",
        ref_name: "main",
        ref_commit_oid: "e62177f1865f707cc9bcc7428c1c029fffa13bf3",
        root_tree_entry_oid: "5aa68b7280995a92990358f81c2145c12433104a",
        path_object_oid: "c790eda2963067baf3ba366b2ba3dea52c944660",
        path_object_type: :blob,
        path_object_mode: 0o100644,
        path_object_size: 8,
    )

    assert_equal(expected, content_metadata)
  end

  test "return cached result when repo didn't change" do
    enable_feature_flag(:contents_metadata_with_cache)

    repository = create(:repository, from_example: :repository_contents_test)

    GitHub.dogstats.reset
    original_content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom")
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])

    GitHub.dogstats.reset
    assert_equal(original_content_metadata, Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom"))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:hit"])
  end

  test "do not return cached result if repo changes" do
    enable_feature_flag(:contents_metadata_with_cache)

    repository = create(:repository, from_example: :repository_contents_test)

    GitHub.dogstats.reset
    original_content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom")
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])

    commit = perform_commit_to(repository, "main")

    GitHub.dogstats.reset
    original_content_hash = original_content_metadata.to_h.merge(head_oid: commit.oid)
    assert_equal(Repositories::Contents::Metadata.new(**original_content_hash), Repositories.domain.contents.metadata_by_ref_and_path(repository: repository, ref: "custom"))
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:metadata_by_ref_and_path", "result:miss"])
  end

  def perform_commit_to(repository, ref)
    repository.heads.find(ref).append_commit({
      message: "change stuff",
      committer: repository.owner,
      author: repository.owner,
    }, repository.owner)
  end
end
