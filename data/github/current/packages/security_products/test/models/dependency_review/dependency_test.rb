# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_review_test_helper"

class DependencyTest < GitHub::TestCase
  include DependencyReviewTestHelper

  setup do
    @snapshot_diff = stubbed_snapshot_diff_response
    @manifest = DependencyReview::Manifest.new(path: "/some/package-lock.json", type: :PACKAGE_MANAGER_NPM)
  end

  test "removed dependencies from twirp" do
    @removed_dependency = @snapshot_diff.changed_manifests[0].dependencies[0]
    dependency = DependencyReview::Dependency.from_twirp(@manifest, @removed_dependency)
    assert_equal :removed, dependency.change_type
    assert_equal @manifest, dependency.manifest
    assert_equal "mongrel", dependency.package_name
    assert_equal "1.3.0", dependency.version
    assert_equal "pkg:gem/mongrel@1.3.0", dependency.purl
    assert_equal :runtime, dependency.scope
  end

  test "updated dependencies from twirp" do
    @updated_dependency = @snapshot_diff.changed_manifests[0].dependencies[1]
    dependency = DependencyReview::Dependency.from_twirp(@manifest, @updated_dependency)
    assert_equal :updated, dependency.change_type
    assert_equal @manifest, dependency.manifest
    assert_equal "daemons", dependency.package_name
    assert_equal "1.0.3", dependency.version
    assert_equal "pkg:gem/daemons@1.0.3", dependency.purl
    assert_equal :development, dependency.scope
  end

  test "added dependencies from twirp" do
    @added_dependency = @snapshot_diff.changed_manifests[1].dependencies[0]
    dependency = DependencyReview::Dependency.from_twirp(@manifest, @added_dependency)
    assert_equal :added, dependency.change_type
    assert_equal @manifest, dependency.manifest
    assert_equal "pandas", dependency.package_name
    assert_equal "1.3.0", dependency.version
    assert_equal "pkg:pypi/pandas@1.3.0", dependency.purl
  end

  test "removed dependency from a removed manifest from twirp" do
    @removed_dependency_from_removed_manifest = @snapshot_diff.changed_manifests[2].dependencies[0]
    dependency = DependencyReview::Dependency.from_twirp(@manifest, @removed_dependency_from_removed_manifest)
    assert_equal :removed, dependency.change_type
    assert_equal @manifest, dependency.manifest
    assert_equal "gemA", dependency.package_name
    assert_equal "1.1.0", dependency.version
  end

  test "'metadata' fields are translated" do
    @added_dependency = @snapshot_diff.changed_manifests[1].dependencies[0]
    dependency = DependencyReview::Dependency.from_twirp(@manifest, @added_dependency)
    assert_equal :added, dependency.change_type
    assert_equal [4, 5], dependency.github_vulnerability_range_ids
    assert_equal DateTime.new(1986, 3, 30, 1, 1, 1), dependency.published_at
    assert_equal "MIT", dependency.license
    assert_equal "some/repo", dependency.repo_nwo
    assert_equal 120000, dependency.dependents_count
  end

  test "leading = signs are stripped from version" do
    manifest = DependencyReview::Manifest.new(path: "/some/path", type: :PACKAGE_MANAGER_NPM)
    dependency = create_mock_dependency(
      package_name: "sample_package",
      version: "= 1.2.3",
      manifest: manifest,
    )

    assert_equal "1.2.3", dependency.version
  end

  test "github_vulnerability_range_ids is to_a'ed" do
    manifest = DependencyReview::Manifest.new(path: "/some/path", type: :PACKAGE_MANAGER_NPM)
    mock_array_like = Minitest::Mock.new
    expected_return = [1, 2, 3]
    mock_array_like.expect(:to_a, expected_return)
    dependency = create_mock_dependency(
      manifest: manifest,
      github_vulnerability_range_ids: mock_array_like,
    )
    mock_array_like.verify

    assert_equal expected_return, dependency.github_vulnerability_range_ids
  end

  test "published_at is not a protobuf object" do
    manifest = DependencyReview::Manifest.new(path: "/some/path", type: :PACKAGE_MANAGER_NPM)
    expected_datetime = DateTime.new(2014, 2, 1)
    timestamp_to_pass = Google::Protobuf::Timestamp.new
    timestamp_to_pass.from_time(expected_datetime)
    dependency = create_mock_dependency(
      manifest: manifest,
      published_at: timestamp_to_pass
    )

    assert_equal DateTime, dependency.published_at.class
    assert_equal expected_datetime, dependency.published_at
  end
end
