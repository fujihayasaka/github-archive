# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequest::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = %w()

    assert_equal expected_public_subject_types, PullRequest::Resources::PUBLIC_SUBJECT_TYPES

    pull_request = PullRequest.new
    expected_public_subject_types.each do |st|
      assert pull_request.resources.respond_to?(st.to_sym), "pull request resources should include #{st}"
    end
  end

  test "PREVIEW_SUBJECTS_AND_FEATURE_FLAGS" do
    expected_preview_subjects = {
      "sarifs" => :pr_code_scanning_analysis
    }

    assert_equal expected_preview_subjects, PullRequest::Resources::PREVIEW_SUBJECTS_AND_FEATURE_FLAGS
  end

  test "ENTERPRISE_SUBJECT_TYPES" do
    enterprise_subject_types = %w()
    assert_equal enterprise_subject_types, PullRequest::Resources::ENTERPRISE_SUBJECT_TYPES
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "PullRequest", PullRequest::Resources::ABILITY_TYPE_PREFIX
  end

  test "WRITEONLY_SUBJECT_TYPES" do
    expected_readonly_subject_types = %w(
      sarifs
    )

    assert_same_elements expected_readonly_subject_types, PullRequest::Resources::WRITEONLY_SUBJECT_TYPES

    pull_request = PullRequest.new
    expected_readonly_subject_types.each do |st|
      assert pull_request.resources.respond_to?(st.to_sym), "pull request resources should include #{st}"
    end
  end

  test "#pull_request returns the parent pull request" do
    pull_request = PullRequest.new
    assert_equal pull_request, T.unsafe(pull_request.resources).pull_request
  end
end
