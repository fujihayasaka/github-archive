# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependency_graph_helpers"

class DependenciesDependencyTest < GitHub::TestCase
  include PushTestHelper
  include DependencyGraphHelpers

  setup do
    # Ensure dependency graph preview is disabled for github-all-features build
    disable_feature_flag(:dependency_graph_preview)

    if GitHub.enterprise?
      GitHub.stubs(
        dependency_graph_enabled?: true,
        dotcom_connection_enabled?: true,
        ghe_content_analysis_enabled?: true,
      )
    end

    @user = create(:organization)
    @repository = create(:repository, owner: @user, from_example: :initial_commit_ruby_library)

    org = create(:organization, plan: GitHub::Plan.business_plus)
    @business_plus_repo = create(:public_repository, owner: org, from_example: :initial_commit_ruby_library)
  end

  test "has_manifests? calls dg-api" do
    stub_has_manifests_query(has_manifests: true)
    assert @repository.has_manifests?

    stub_has_manifests_query(has_manifests: false)
    refute @repository.has_manifests?
  end

  test "has_manifests? returns false for NotFoundError" do
    FakeDependencyGraphAPIServer.fail_with_http_status = :not_found
    refute @repository.has_manifests?
  end

  test "has_manifests? raises HasManifestUnknownError for other errors" do
    FakeDependencyGraphAPIServer.fail_with_http_status = :unknown
    assert_raises(DependencyGraph::BaseTwirpClient::Error) do
      @repository.has_manifests?
    end
  end

  if GitHub.enterprise?
    test "max_manifest_files is 600 by default on GHES" do
      assert_equal 600, @repository.max_manifest_files
    end
  else
    test "max_manifest_files is 150 by default" do
      # We might be in the `github_all_features` ci environment
      disable_feature_flag(:dependency_graph_max_manifests_high, @repository)
      assert_equal 150, @repository.max_manifest_files
    end
  end

  test "max_manifest_files is 600 when we turn on a feature flag" do
    enable_feature_flag(:dependency_graph_max_manifests_high, @repository)
    assert_equal 600, @repository.max_manifest_files
  end

  test "max_manifest_files is 600 when for enterprise plans" do
    if GitHub.enterprise?
      assert_equal 600, @repository.max_manifest_files
    else
      enable_feature_flag(:dependency_graph_disable_ghec_limits, @business_plus_repo)
      assert_equal 600, @business_plus_repo.max_manifest_files
    end
  end

  unless GitHub.enterprise?
    test "max_manifest_files is 150 when no owner is present" do
      @repository.stubs(:owner).returns(nil)
      assert_equal 150, @repository.max_manifest_files
    end
  end
end
