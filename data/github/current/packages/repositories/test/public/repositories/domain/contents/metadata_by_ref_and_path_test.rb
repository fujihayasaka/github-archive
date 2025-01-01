# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::MetadataByRefAndPathTest < GitHub::TestCase

  BASE_REPO_METADATA = {
    head_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba"
  }.freeze

  DEFAULT_BRANCH_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
    ref_name: "main",
    ref_type: :head,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  TAG_V1_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "5a87dd0219beebaba7574d82cfa1f348a2a616de",
    ref_name: "v1",
    ref_type: :tag,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  TAG_V2_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "8a2253252eec0aabc0ffde593c56a951ad70f8c9",
    ref_name: "v2",
    ref_type: :tag,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  BRANCH_CUSTOM_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "46b5b1e7eabed5d93b4933315dcb395ec65e1f7a",
    ref_name: "custom",
    ref_type: :head,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  OID_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "61a4709fef5564d5910963dd516efc856fc5241e",
    ref_name: "61a4709fef5564d5910963dd516efc856fc5241e",
    ref_type: :oid,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  CUSTOM_REF_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "46b5b1e7eabed5d93b4933315dcb395ec65e1f7a",
    ref_name: "refs/my-custom-ref",
    ref_type: :qualified_ref,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  SHORT_OID_METADATA = OID_METADATA.merge(
    ref_type: :revision,
    ref_name: "61a4709",
  ).freeze

  GH_REF_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
    ref_name: "refs/__gh__/hidden",
    ref_type: :qualified_ref,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  BRANCH_AND_TAG_SAME_NAME_METADATA = BASE_REPO_METADATA.merge(
    ref_commit_oid: "6bf267f6ef0b29c05ce47258b99422848d2799ba",
    ref_name: "branch_and_tag",
    ref_type: :head,
    root_tree_entry_oid: "9c7081a186314bff683b50751c5dd03b12fb185b"
  ).freeze

  fixtures do
    @repo = create(:repository, from_example: :repository_contents_test)
    @empty_repo = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd
  end

  test "empty repository" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: @empty_repo)

    assert_equal(Repositories::Contents::Metadata::EMPTY_REPOSITORY, content_metadata)
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

  test "by branch full ref name" do
    content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: @repo,
      ref: "refs/heads/custom",
      path: "dir"
    )

    expected = Repositories::Contents::Metadata.new(
      **BRANCH_CUSTOM_METADATA.merge(
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree
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
        path_object_oid: "9daeafb9864cf43055ae93beb0afd6c7d144bfa4",
        path_object_type: :blob
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
        path_object_type: :blob
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
        path_object_type: :blob
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
        path_object_type: :blob
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
        path_object_oid: "29a422c19251aeaeb907175e9b3219a9bed6c616",
        path_object_type: :tree
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
          path_object_oid: "9c7081a186314bff683b50751c5dd03b12fb185b",
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
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

      # The oid and short oid gets the same result when resolving the root directory.
      # Given oid being more specific than short oid,
      # we will return OID_METADATA instead of SHORT_OID_METADATA
      expected = Repositories::Contents::Metadata.new(
        **OID_METADATA.merge(
          ref_name: "61a4709",
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
          path_object_type: :tree
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
          path_object_type: :blob
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
          path_object_type: :submodule
        )
      )

      assert_equal(expected, content_metadata)
    end
  end
end
