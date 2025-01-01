# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::SubmoduleByCommitAndPath < GitHub::TestCase

  fixtures do
    @repo = create(:repository, from_example: :submodules_contents)
  end

  setup do
    Spokesd.enable_spokesd
  end

  test "returns multiple submodules" do
    expected_submodules = [{
      path: "submodule1",
      oid:  "dfb8173e115723682a20d3f5c70c89700e28f794",
      name: "submodule1",
      url:  "../submodule1",
    },
    {
      path: "dir/submodule2",
      oid:  "e0f68688dac72cbb47c3fb94df3590c7a98a2b8d",
      name: "dir/submodule2",
      url:  "../submodule2",
    },
    {
      path: "submodule3",
      oid:  "6ce51b8c7af6d12f94878c29131e5b13e9e49c75",
      name: nil,
      url:  nil,
    },
    {
      path: "submodule4",
      oid:  "1953d04d61d8e7de3aee7a653c7dc856d8d71222",
      name: "great-submodule",
      url:  "../submodule4/",
    },
    {
      path: "submodule5",
      oid:  "816eb351c1b45a187c38be88b34637d47dc0d34b",
      name: "foo",
      url:  "../submodule5",
    }]

    not_expected_submodules = %w[
      submodule6
      dir
    ]

    paths = expected_submodules.map { |submodule| submodule[:path] }
    paths += not_expected_submodules

    submodules = Repositories.domain.contents.submodules_by_commit_and_paths(
      repository: @repo, commit_oid: "6df348a7f38305373ff44d16ad607aa1cb302a3c", paths:
    )

    submodules.each_with_index do |submodule, idx|
      expected_submodule = T.must(expected_submodules[idx])
      assert_equal(expected_submodule[:path], submodule.path)
      assert_equal(expected_submodule[:oid], submodule.oid)
      if expected_submodule[:name].nil?
        assert_nil(submodule.name)
      else
        assert_equal(expected_submodule[:name], submodule.name)
      end
      if expected_submodule[:url].nil?
        assert_nil(submodule.url)
      else
        assert_equal(expected_submodule[:url], submodule.url)
      end
    end

    not_expected_submodules.each do |submodule|
      assert_nil(submodules.find { |sub| sub.path == submodule })
    end
  end

  test "returns a single submodule" do
    submodules = Repositories.domain.contents.submodules_by_commit_and_paths(
      repository: @repo, commit_oid: "6df348a7f38305373ff44d16ad607aa1cb302a3c", paths: ["submodule1"]
    )

    assert_equal 1, submodules.size
    submodule = T.must(submodules[0])
    assert_equal "submodule1", submodule.path
    assert_equal "dfb8173e115723682a20d3f5c70c89700e28f794", submodule.oid
    assert_equal "submodule1", submodule.name
    assert_equal "../submodule1", submodule.url
  end

  test "raises if commit is not found" do
    assert_raises(SpokesAPI::TwirpServerError, "git-show-paths: exit status 128") do
      Repositories.domain.contents.submodules_by_commit_and_paths(
        repository: @repo,
        commit_oid: "955da6b0007b76a160dd62d84bf8de19d09b6f7c",
        paths: ["submodule1"]
      )
    end
  end
end
