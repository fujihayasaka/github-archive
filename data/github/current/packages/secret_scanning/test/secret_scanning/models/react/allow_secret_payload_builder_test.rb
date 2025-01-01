# typed: true
# frozen_string_literal: true

require "test_helper"

class AllowSecretPayloadBuilderTest < GitHub::TestCase

  fixtures do
    @user = create(:user, login: "monalisa")
    @org = create(:organization, admin: @user, name: "github")

    @repo = create(:repository, owner: @org, name: "octocat")
    @payload_builder = SecretScanning::Models::React::AllowSecretPayloadBuilder.new(@repo, @user).freeze

    @public_org_repo = create(:public_repository, owner: @org, name: "public-org-repo")
    @payload_builder_public_org_repo = SecretScanning::Models::React::AllowSecretPayloadBuilder.new(@public_org_repo, @user).freeze

    @free_public_repo = create(:public_repository, owner: @user, name: "free-public-repo")
    @payload_builder_free_public_repo = SecretScanning::Models::React::AllowSecretPayloadBuilder.new(@free_public_repo, @user).freeze
  end

  setup do
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(true)

    @bypass_placeholder = SecretScanning::Models::BypassPlaceholder.new(
      ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
      signature: "a5b554f59c10b2515b017b650cff7bdb80c134c650770f6f80a0a0f3b3f6503c",
      token_metadata: SecretScanning::Models::TokenMetadata.new(
        token_type: "SECRET_SCANNING_SAMPLE_TOKEN",
        slug: "secret_scanning_sample_token",
        label: "GitHub Secret Scanning",
        provider: "GitHub Secret Scanning",
      ),
      token_type: "SECRET_SCANNING_SAMPLE_TOKEN",
      actor_id: @user.id
    )

    @blob_edit_first_secret_location = {
      start_line: 3,
      end_line: 3,
      start_line_byte_position: 10,
      end_line_byte_position: 20,
    }
  end

  context "payload" do
    test "builds allow secret payload for repo bypass experience with custom push protection message" do
      custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "github", owner_type: "organization", message: "https://test.com")
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

      actual_payload = @payload_builder.page_payload(bypass_placeholder: @bypass_placeholder, limited_user_bypass_experience_only: false)

      assert_equal "github", actual_payload[:owner_display_login]
      assert_equal "octocat", actual_payload[:repo_name]
      assert_equal GitHub.help_url, actual_payload[:help_url]

      assert_equal "GitHub Secret Scanning", actual_payload[:bypass_metadata][:token_label]
      assert_equal "2VQXEauseN3fWZS5NNH6SLQP3di", actual_payload[:bypass_metadata][:placeholder_ksuid]
      assert_equal false, actual_payload[:bypass_metadata][:is_custom_pattern]
      assert_equal false, actual_payload[:bypass_metadata][:limited_user_bypass_experience_only]
      assert_equal "https://test.com", actual_payload[:bypass_metadata][:push_protection_custom_message][:message]
      assert_equal "github", actual_payload[:bypass_metadata][:push_protection_custom_message][:owner_name]
      assert_equal true, actual_payload[:bypass_metadata][:repo_has_secret_scanning_experience]
    end

    test "builds allow secret payload for repo bypass experience for custom pattern secret" do
      custom_pattern_bypass_placeholder = SecretScanning::Models::BypassPlaceholder.new(
        ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        signature: "a5b554f59c10b2515b017b650cff7bdb80c134c650770f6f80a0a0f3b3f6503c",
        token_metadata: SecretScanning::Models::TokenMetadata.new(
          token_type: "cp_1",
          slug: "custom_pattern",
          label: "Custom Pattern",
          provider: "CUSTOM_PATTERN",
        ),
        token_type: "SECRET_SCANNING_SAMPLE_TOKEN",
        actor_id: @user.id
      )

      actual_payload = @payload_builder.page_payload(bypass_placeholder: custom_pattern_bypass_placeholder, limited_user_bypass_experience_only: false)

      assert_equal "Custom Pattern", actual_payload[:bypass_metadata][:token_label]
      assert_equal true, actual_payload[:bypass_metadata][:is_custom_pattern]
    end

    test "builds allow secret payload for repo bypass experience without custom push protection message" do
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(nil)

      actual_payload = @payload_builder.page_payload(bypass_placeholder: @bypass_placeholder, limited_user_bypass_experience_only: false)

      assert_nil actual_payload[:bypass_metadata][:push_protection_custom_message]
    end

    test "builds allow secret payload for user bypass experience on a user-owned free public repo" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(nil)

      actual_payload = @payload_builder_free_public_repo.page_payload(bypass_placeholder: @bypass_placeholder, limited_user_bypass_experience_only: true)

      assert_equal "monalisa", actual_payload[:owner_display_login]
      assert_equal "free-public-repo", actual_payload[:repo_name]
      assert_equal true, actual_payload[:bypass_metadata][:limited_user_bypass_experience_only]
      assert_nil actual_payload[:bypass_metadata][:push_protection_custom_message]
      assert_equal false, actual_payload[:bypass_metadata][:repo_has_secret_scanning_experience]
    end

    test "builds allow secret payload for user bypass experience on a org-owned public repo with custom push protection message" do
      custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "github", owner_type: "organization", message: "https://test.com")
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

      actual_payload = @payload_builder_public_org_repo.page_payload(bypass_placeholder: @bypass_placeholder, limited_user_bypass_experience_only: true)

      assert_equal "github", actual_payload[:owner_display_login]
      assert_equal "public-org-repo", actual_payload[:repo_name]
      assert_equal true, actual_payload[:bypass_metadata][:limited_user_bypass_experience_only]
      assert_equal "https://test.com", actual_payload[:bypass_metadata][:push_protection_custom_message][:message]
      assert_equal "github", actual_payload[:bypass_metadata][:push_protection_custom_message][:owner_name]
      assert_equal true, actual_payload[:bypass_metadata][:repo_has_secret_scanning_experience]
    end

    test "builds allow secret payload for user bypass experience on a org-owned public repo with enterprise level custom push protection message" do
      custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "github", owner_type: "enterprise", message: "https://test.com")
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

      actual_payload = @payload_builder_public_org_repo.page_payload(bypass_placeholder: @bypass_placeholder, limited_user_bypass_experience_only: true)

      assert_equal "github", actual_payload[:owner_display_login]
      assert_equal "public-org-repo", actual_payload[:repo_name]
      assert_equal true, actual_payload[:bypass_metadata][:limited_user_bypass_experience_only]
      assert_equal "https://test.com", actual_payload[:bypass_metadata][:push_protection_custom_message][:message]
      assert_equal "github", actual_payload[:bypass_metadata][:push_protection_custom_message][:owner_name]
      assert_equal true, actual_payload[:bypass_metadata][:repo_has_secret_scanning_experience]
    end
  end

  context "blob_edit_bypass_metadata" do
    test "builds blob editor bypass metadata payload for repo bypass experience with custom push protection message" do
      custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "github", owner_type: "organization", message: "https://test.com")
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

      blob_edit_payload = @payload_builder.blob_edit_bypass_metadata(
        token_metadata_label: "GitHub Secret Scanning",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: false,
        limited_user_bypass_experience_only: false,
        first_secret_location: @blob_edit_first_secret_location,
      )

      assert_equal "GitHub Secret Scanning", blob_edit_payload[:token_label]
      assert_equal "github", blob_edit_payload[:owner_display_login]
      assert_equal "octocat", blob_edit_payload[:repo_name]
      assert_equal "2VQXEauseN3fWZS5NNH6SLQP3di", blob_edit_payload[:placeholder_ksuid]
      assert_equal false, blob_edit_payload[:is_custom_pattern]
      assert_equal false, blob_edit_payload[:limited_user_bypass_experience_only]
      assert_equal "https://test.com", blob_edit_payload[:push_protection_custom_message][:message]
      assert_equal "github", blob_edit_payload[:push_protection_custom_message][:owner_name]
      assert_equal true, blob_edit_payload[:repo_has_secret_scanning_experience]

      assert_equal 3, blob_edit_payload[:first_secret_location][:start_line]
      assert_equal 3, blob_edit_payload[:first_secret_location][:end_line]
      assert_equal 10, blob_edit_payload[:first_secret_location][:start_line_byte_position]
      assert_equal 20, blob_edit_payload[:first_secret_location][:end_line_byte_position]
    end

    test "builds blob editor bypass metadata payload for repo bypass experience with custom pattern secret" do
      blob_edit_payload = @payload_builder.blob_edit_bypass_metadata(
        token_metadata_label: "Custom Pattern",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: true,
        limited_user_bypass_experience_only: false,
        first_secret_location: @blob_edit_first_secret_location,
      )

      assert_equal "Custom Pattern", blob_edit_payload[:token_label]
      assert_equal "2VQXEauseN3fWZS5NNH6SLQP3di", blob_edit_payload[:placeholder_ksuid]
      assert_equal true, blob_edit_payload[:is_custom_pattern]
    end

    test "builds blob editor bypass metadata payload for repo bypass experience without custom push protection message" do
      SecretScanning::Features::Org::PushProtection.any_instance.stubs(:custom_message_active?).returns(false)
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(nil)

      blob_edit_payload = @payload_builder.blob_edit_bypass_metadata(
        token_metadata_label: "Custom Pattern",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: true,
        limited_user_bypass_experience_only: false,
        first_secret_location: @blob_edit_first_secret_location,
      )

      assert_nil blob_edit_payload[:push_protection_custom_message]
    end

    test "builds blob editor bypass metadata payload for user bypass experience on a user-owned free public repo" do
      SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:enabled?).returns(false)
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(nil)

      blob_edit_payload = @payload_builder_free_public_repo.blob_edit_bypass_metadata(
        token_metadata_label: "GitHub Secret Scanning",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: false,
        limited_user_bypass_experience_only: true,
        first_secret_location: @blob_edit_first_secret_location,
      )

      assert_equal true, blob_edit_payload[:limited_user_bypass_experience_only]
      assert_nil blob_edit_payload[:push_protection_custom_message]
      assert_equal false, blob_edit_payload[:repo_has_secret_scanning_experience]
    end

    test "builds blob editor bypass metadata payload for user bypass experience on a org-owned public repo with custom push protection message" do
      custom_msg = SecretScanning::Models::PushProtection::CustomMessage.new(owner_name: "github", owner_type: "organization", message: "https://test.com")
      SecretScanning::Services::PushProtectionService.stubs(:get_custom_message).returns(custom_msg)

      blob_edit_payload = @payload_builder_public_org_repo.blob_edit_bypass_metadata(
        token_metadata_label: "GitHub Secret Scanning",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: false,
        limited_user_bypass_experience_only: true,
        first_secret_location: @blob_edit_first_secret_location,
      )

      assert_equal true, blob_edit_payload[:limited_user_bypass_experience_only]
      assert_equal "https://test.com", blob_edit_payload[:push_protection_custom_message][:message]
      assert_equal "github", blob_edit_payload[:push_protection_custom_message][:owner_name]
      assert_equal true, blob_edit_payload[:repo_has_secret_scanning_experience]
    end

    test "builds blob editor bypass metadata payload for repo bypass experience on a delegated bypass enabled repo" do
      SecretScanning::Services::DelegatedBypassService.stubs(:use_delegated_bypass_flow).with(@repo, @user).returns(true)

      blob_edit_payload = @payload_builder.blob_edit_bypass_metadata(
        token_metadata_label: "GitHub Secret Scanning Token",
        bypass_placeholder_ksuid: "2VQXEauseN3fWZS5NNH6SLQP3di",
        is_custom_pattern: false,
        limited_user_bypass_experience_only: false,
        first_secret_location: @blob_edit_first_secret_location,
        rule_suite_id: 1,
      )

      assert blob_edit_payload[:use_delegated_bypass_flow]
      assert_equal 1, blob_edit_payload[:rule_suite_id]
    end
  end
end
