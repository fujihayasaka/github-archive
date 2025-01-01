# typed: true
# frozen_string_literal: true

require "test_helper"

class Repository::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = %w(
      actions
      actions_variables
      administration
      attestations
      checks
      codespaces
      codespaces_lifecycle_admin
      codespaces_metadata
      codespaces_secrets
      contents
      dependabot_secrets
      deployments
      discussions
      environments
      issues
      merge_queues
      metadata
      packages
      pages
      pull_requests
      repository_advisories
      repository_custom_properties
      repository_hooks
      repository_projects
      secret_scanning_alerts
      secrets
      security_events
      single_file
      statuses
      vulnerability_alerts
      workflows
    )

    assert_equal expected_public_subject_types, Repository::Resources::PUBLIC_SUBJECT_TYPES

    repo = Repository.new
    expected_public_subject_types.each do |st|
      assert repo.resources.respond_to?(st.to_sym), "repo resources should include #{st}"
    end
  end

  test "PREVIEW_SUBJECTS_AND_FEATURE_FLAGS" do
    expected_preview_subjects = {
      "pull_requests_from_forks" => :pull_requests_from_forks_resource,
      "pull_requests_comment_only_reviews" => :pull_requests_comment_only_reviews_resource,
      "repository_announcement_banners" => :enterprise_banners_repo_level,
    }

    assert_equal expected_preview_subjects, Repository::Resources::PREVIEW_SUBJECTS_AND_FEATURE_FLAGS
  end

  test "ENTERPRISE_SUBJECT_TYPES" do
    enterprise_subject_types = %w(repository_pre_receive_hooks)
    assert_equal enterprise_subject_types, Repository::Resources::ENTERPRISE_SUBJECT_TYPES
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "Repository", Repository::Resources::ABILITY_TYPE_PREFIX
  end

  test "READONLY_SUBJECT_TYPES" do
    expected_readonly_subject_types = %w(
      codespaces_metadata
      metadata
    )

    assert_same_elements expected_readonly_subject_types, Repository::Resources::READONLY_SUBJECT_TYPES

    repository = Repository.new
    expected_readonly_subject_types.each do |st|
      assert repository.resources.respond_to?(st.to_sym), "repository resources should include #{st}"
    end
  end

  test "ADMINABLE_SUBJECT_TYPES" do
    expected_adminable_subject_types = %w(
      repository_projects
    )

    assert_same_elements expected_adminable_subject_types, Repository::Resources::ADMINABLE_SUBJECT_TYPES

    repository = Repository.new
    expected_adminable_subject_types.each do |st|
      assert repository.resources.respond_to?(st.to_sym), "repository resources should include #{st}"
    end
  end

  test "EXCLUDED_SUBJECT_TYPES_FOR_TYPE" do
    expected_excluded_types_for_type = {
      UserProgrammaticAccess => %w(checks packages repository_projects single_file),
    }

    assert_same_hash expected_excluded_types_for_type, Repository::Resources::EXCLUDED_SUBJECT_TYPES_FOR_TYPE
  end

  test "public subject types are not in preview or enterprise subject types" do
    Repository::Resources::PUBLIC_SUBJECT_TYPES.each do |subject|
      refute_includes Repository::Resources::PREVIEW_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and feature-flagged subject types"
      refute_includes Repository::Resources::ENTERPRISE_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and enterprise subject types"
    end
  end

  test "#repository returns the parent repository" do
    repo = Repository.new
    assert_equal repo, repo.resources.repository
  end
end
