# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_review_test_helper"

class ManifestTest < GitHub::TestCase
  include DependencyReviewTestHelper

  setup do
    @snapshot_diff = stubbed_snapshot_diff_response
  end

  test "removed and updated dependencies collection in manifest from twirp" do
    manifest_with_remove_and_change = @snapshot_diff.changed_manifests[0]
    manifest = DependencyReview::Manifest.from_twirp(manifest_with_remove_and_change)

    assert_equal "Gemfile", manifest.path
    assert_equal :PACKAGE_MANAGER_RUBYGEMS, manifest.type
    assert_equal 1, manifest.removed_dependencies.count
    assert_equal 1, manifest.updated_dependencies.count
    assert_equal 0, manifest.added_dependencies.count
  end

  test "added dependencies collection in manifest from twirp" do
    manifest_with_add = @snapshot_diff.changed_manifests[1]
    manifest = DependencyReview::Manifest.from_twirp(manifest_with_add)

    assert_equal "src/requirements.txt", manifest.path
    assert_equal :PACKAGE_MANAGER_PIP, manifest.type
    assert_equal 0, manifest.removed_dependencies.count
    assert_equal 0, manifest.updated_dependencies.count
    assert_equal 1, manifest.added_dependencies.count
  end

  test "removed dependencies collection in removed manifest from twirp" do
    removed_manifest = @snapshot_diff.changed_manifests[2]
    manifest = DependencyReview::Manifest.from_twirp(removed_manifest)

    assert_equal "src/Gemfile", manifest.path
    assert_equal :PACKAGE_MANAGER_RUBYGEMS, manifest.type
    assert_equal 2, manifest.removed_dependencies.count
  end
end
