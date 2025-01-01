# typed: true
# frozen_string_literal: true

require "test_helper"

class User::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = %w(
      blocking
      codespaces_user_secrets
      emails
      followers
      gpg_keys
      gists
      git_signing_ssh_public_keys
      interaction_limits
      keys
      starring
      user_events
      plan
      watching
      profile
      private_repository_invitations
      copilot_editor_context
      knowledge_bases
      copilot_messages
    )

    assert_same_elements expected_public_subject_types, User::Resources::PUBLIC_SUBJECT_TYPES
  end

  test "PREVIEW_SUBJECTS_AND_FEATURE_FLAGS" do
    expected_preview_subjects = {
      "user_models" => :github_models_read_access_for_users
    }

    assert_equal expected_preview_subjects, User::Resources::PREVIEW_SUBJECTS_AND_FEATURE_FLAGS
  end

  test "CONNECT_ONLY_SUBJECT_TYPES" do
    expected_connect_only_subject_types = %w(
      external_contributions
    )

    assert_same_elements expected_connect_only_subject_types, User::Resources::CONNECT_ONLY_SUBJECT_TYPES
  end

  test "ENTERPRISE_SUBJECT_TYPES" do
    assert_empty User::Resources::ENTERPRISE_SUBJECT_TYPES
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "User", User::Resources::ABILITY_TYPE_PREFIX
  end

  test "READONLY_SUBJECT_TYPES" do
    expected_readonly_subject_types = %w(
      plan
      private_repository_invitations
      copilot_messages
      copilot_editor_context
      user_events
      user_models
    )

    assert_same_elements expected_readonly_subject_types, User::Resources::READONLY_SUBJECT_TYPES

    user = User.new
    expected_readonly_subject_types.each do |st|
      assert user.resources.respond_to?(st.to_sym), "user resources should include #{st}"
    end
  end

  test "WRITEONLY_SUBJECT_TYPES" do
    expected_writeonly_subject_types = %w(
      gists
      profile
    )

    assert_same_elements expected_writeonly_subject_types, User::Resources::WRITEONLY_SUBJECT_TYPES

    user = User.new
    expected_writeonly_subject_types.each do |st|
      assert user.resources.respond_to?(st.to_sym), "user resources should include #{st}"
    end
  end

  test "EXCLUDED_SUBJECT_TYPES_FOR_TYPE" do
    expected_subject_types = {
      Integration => %w(private_repository_invitations)
    }

    assert_equal expected_subject_types, User::Resources::EXCLUDED_SUBJECT_TYPES_FOR_TYPE
  end

  test "public subject types are not in preview, connect-only or enterprise subject types" do
    User::Resources::PUBLIC_SUBJECT_TYPES.each do |subject|
      refute_includes User::Resources::PREVIEW_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and feature-flagged subject types"
      refute_includes User::Resources::CONNECT_ONLY_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and connect-only subject types"
      refute_includes User::Resources::ENTERPRISE_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and enterprise subject types"
    end
  end

  test "#user returns the parent user" do
    user = User.new
    assert_equal user, user.resources.user
  end

  test "individual #resources are of type 'OauthAuthorization::AbilityCollection'" do
    user = User.new
    assert user.resources.emails.is_a?(OauthAuthorization::AbilityCollection), "should be an OauthAuthorization::AbilityCollection"
  end
end
